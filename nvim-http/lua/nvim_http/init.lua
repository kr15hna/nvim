local M = {}

local config = {
  history_dir = ".nvim-http-history",
  oauth_cache_file = ".nvim-http.oauth-cache.json",
  globals = {},
  vars_file = ".nvim-http.vars.lua",
  split = {
    direction = "botright",
    size = 16,
  },
}
local commands_created = false
local spinner = {
  timer = nil,
  frame = 1,
  message = "",
}
local spinner_stop
local session_overrides = {}
local augroup_id = nil

local function merge(dst, src)
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      merge(dst[k], v)
    else
      dst[k] = v
    end
  end
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ensure_dir(path)
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function deep_copy(v)
  return vim.deepcopy(v)
end

local function sanitize_name(name)
  if not name or name == "" then
    return "request"
  end
  return name:gsub("[^%w%-_]+", "_")
end

local function interpolate(input, vars)
  return (input:gsub("{{%s*([%w_%.%-]+)%s*}}", function(key)
    local parts = vim.split(key, ".", { plain = true })
    local cur = vars
    for _, p in ipairs(parts) do
      if type(cur) ~= "table" then
        return ""
      end
      cur = cur[p]
      if cur == nil then
        return ""
      end
    end
    return tostring(cur)
  end))
end

local function load_project_globals()
  local file = config.vars_file
  if not file or file == "" then
    return {}
  end

  local cwd = vim.fn.getcwd()
  local path = cwd .. "/" .. file
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local chunk, err = loadfile(path)
  if not chunk then
    return nil, "failed loading vars file " .. file .. ": " .. err
  end

  local ok, result = pcall(chunk)
  if not ok then
    return nil, "failed running vars file " .. file .. ": " .. result
  end

  if result == nil then
    return {}
  end
  if type(result) ~= "table" then
    return nil, "vars file must return a table: " .. file
  end
  return result
end

local function merged_vars()
  local merged = deep_copy(config.globals or {})
  local project_globals, vars_err = load_project_globals()
  if not project_globals then
    return nil, vars_err
  end
  merge(merged, project_globals)
  merge(merged, session_overrides)
  return merged
end

local function json_decode(input)
  if not input or input == "" then
    return nil, "empty json input"
  end
  if vim.json and vim.json.decode then
    local ok, out = pcall(vim.json.decode, input)
    if ok then
      return out
    end
  end
  local ok, out = pcall(vim.fn.json_decode, input)
  if ok then
    return out
  end
  return nil, "invalid json"
end

local function json_encode(value)
  if vim.json and vim.json.encode then
    local ok, out = pcall(vim.json.encode, value)
    if ok then
      return out
    end
  end
  local ok, out = pcall(vim.fn.json_encode, value)
  if ok then
    return out
  end
  return nil, "failed to encode json"
end

local function read_json_file(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local lines = vim.fn.readfile(path)
  local raw = table.concat(lines, "\n")
  if trim(raw) == "" then
    return {}
  end
  local obj, err = json_decode(raw)
  if not obj then
    return nil, "failed parsing json file " .. path .. ": " .. err
  end
  if type(obj) ~= "table" then
    return nil, "json file " .. path .. " must contain an object"
  end
  return obj
end

local function write_json_file(path, obj)
  local encoded, err = json_encode(obj)
  if not encoded then
    return nil, "failed encoding json for " .. path .. ": " .. err
  end
  local lines = vim.split(encoded, "\n", { plain = true })
  vim.fn.writefile(lines, path)
  return true
end

local function parse_http_request(lines)
  local req = {
    method = nil,
    url = nil,
    headers = {},
    body = "",
  }

  local idx = 1
  while idx <= #lines and trim(lines[idx]) == "" do
    idx = idx + 1
  end

  if idx > #lines then
    return nil, "request section is empty"
  end

  local request_line = trim(lines[idx])
  local method, url = request_line:match("^(%u+)%s+(%S+)$")
  if not method or not url then
    return nil, "invalid request line: " .. request_line
  end

  req.method = method
  req.url = url
  idx = idx + 1

  while idx <= #lines do
    local line = lines[idx]
    if trim(line) == "" then
      idx = idx + 1
      break
    end

    local key, value = line:match("^([^:]+):%s*(.*)$")
    if not key then
      return nil, "invalid header line: " .. line
    end

    table.insert(req.headers, { key = trim(key), value = trim(value) })
    idx = idx + 1
  end

  if idx <= #lines then
    req.body = table.concat(vim.list_slice(lines, idx, #lines), "\n")
  end

  return req
end

local function apply_default_headers(req, vars)
  local defaults = vars and vars.default_headers
  if type(defaults) ~= "table" then
    return
  end

  local seen = {}
  for _, h in ipairs(req.headers or {}) do
    if h.key then
      seen[h.key:lower()] = true
    end
  end

  if vim.tbl_islist(defaults) then
    for _, item in ipairs(defaults) do
      if type(item) == "table" and item.key and item.value then
        local k = tostring(item.key)
        if not seen[k:lower()] then
          table.insert(req.headers, { key = k, value = tostring(item.value) })
          seen[k:lower()] = true
        end
      end
    end
    return
  end

  for k, v in pairs(defaults) do
    local key = tostring(k)
    if not seen[key:lower()] then
      table.insert(req.headers, { key = key, value = tostring(v) })
      seen[key:lower()] = true
    end
  end
end

local function parse_sections(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local sections = {}

  local current = {
    name = "request_1",
    kind = "request",
    lines = {},
    start_line = 1,
    ending_line = 1,
  }

  local function flush()
    current.ending_line = current.start_line + #current.lines - 1
    if #current.lines > 0 then
      table.insert(sections, current)
    end
  end

  local function only_blank(acc)
    for _, v in ipairs(acc) do
      if trim(v) ~= "" then
        return false
      end
    end
    return true
  end

  for i, line in ipairs(lines) do
    local marker_name = line:match("^###%s*(.*)$")
    if marker_name ~= nil then
      flush()
      local name = trim(marker_name)
      current = {
        name = name ~= "" and name or ("request_" .. tostring(#sections + 1)),
        kind = "request",
        lines = {},
        start_line = i + 1,
        ending_line = i + 1,
      }
    else
      local script_type = line:match("^%s*@script%s+(%w+)%s*$")
      if script_type == "lua" and (#current.lines == 0 or only_blank(current.lines)) then
        current.kind = "script"
      end
      table.insert(current.lines, line)
    end
  end

  flush()

  return sections
end

local function section_at_cursor(sections)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  for _, s in ipairs(sections) do
    if cursor >= s.start_line and cursor <= s.ending_line then
      return s
    end
  end
  return nil
end

local function run_lua_script(section, ctx)
  local body = table.concat(vim.list_slice(section.lines, 2, #section.lines), "\n")
  local fn, err = load(body, "nvim-http:" .. section.name, "t", {
    ctx = ctx,
    vars = ctx.vars,
    last = ctx.last,
    vim = vim,
  })

  if not fn then
    return nil, "script compile error in " .. section.name .. ": " .. err
  end

  local ok, runtime_err = pcall(fn)
  if not ok then
    return nil, "script runtime error in " .. section.name .. ": " .. runtime_err
  end

  return true
end

local function build_curl_args(req, include_headers)
  local args = {
    "curl",
    "-sS",
    "-X",
    req.method,
    req.url,
  }
  if include_headers ~= false then
    table.insert(args, 3, "-i")
  end

  for _, header in ipairs(req.headers) do
    table.insert(args, "-H")
    table.insert(args, string.format("%s: %s", header.key, header.value))
  end

  if req.body and req.body ~= "" then
    table.insert(args, "--data")
    table.insert(args, req.body)
  end

  table.insert(args, "-w")
  table.insert(args, "\n__NVIM_HTTP_META__%{http_code} %{time_total}\n")

  return args
end

local function parse_curl_output(lines)
  local cleaned = {}
  for _, line in ipairs(lines) do
    local v = line:gsub("\r$", ""):gsub("\000", "")
    table.insert(cleaned, v)
  end

  local meta_idx = nil
  for i = #cleaned, 1, -1 do
    if cleaned[i]:match("^__NVIM_HTTP_META__") then
      meta_idx = i
      break
    end
  end

  if not meta_idx then
    return {
      raw = table.concat(cleaned, "\n"),
      status = "unknown",
      time_total = "unknown",
    }
  end

  local meta = cleaned[meta_idx]
  local status, time_total = meta:match("^__NVIM_HTTP_META__(%d+)%s+([%d%.]+)$")
  local output = vim.list_slice(cleaned, 1, meta_idx - 1)

  return {
    raw = table.concat(output, "\n"),
    status = status or "unknown",
    time_total = time_total or "unknown",
  }
end

local function spinner_render()
  local frames = { "|", "/", "-", "\\" }
  local frame = frames[spinner.frame] or "|"
  vim.api.nvim_echo({ { string.format("%s %s", frame, spinner.message), "ModeMsg" } }, false, {})
  spinner.frame = (spinner.frame % #frames) + 1
end

local function spinner_start(message)
  spinner_stop()
  local uv = vim.uv or vim.loop
  spinner.message = message or "Running requests..."
  spinner.frame = 1
  spinner.timer = uv.new_timer()
  spinner_render()
  spinner.timer:start(
    120,
    120,
    vim.schedule_wrap(function()
      spinner_render()
    end)
  )
end

spinner_stop = function()
  if spinner.timer then
    spinner.timer:stop()
    spinner.timer:close()
    spinner.timer = nil
  end
  vim.api.nvim_echo({ { "", "Normal" } }, false, {})
end

local function append_multiline(dst, text)
  local parts = vim.split(text or "", "\n", { plain = true })
  for _, part in ipairs(parts) do
    table.insert(dst, part)
  end
end

local function resolve_desired_account(req, vars)
  for _, header in ipairs(req.headers or {}) do
    if header.key and header.key:lower() == "x-lm-desired-account" then
      return header.value
    end
  end
  return (vars and vars.desired_account) or ""
end

local function current_desired_account(vars)
  return (vars and vars.desired_account) or ""
end

local function sync_desired_account_global(vars)
  vim.g.nvim_http_desired_account = current_desired_account(vars)
end

local function refresh_desired_account_global()
  local vars, err = merged_vars()
  if not vars then
    return nil, err
  end
  sync_desired_account_global(vars)
  vim.cmd("redrawstatus")
  return vim.g.nvim_http_desired_account, nil
end

local function confirm_non_get_request(req, vars)
  if req.method == "GET" then
    return true
  end

  local desired_account = resolve_desired_account(req, vars)
  local prompt = table.concat({
    "Non-GET request detected:",
    req.method .. " " .. req.url,
    "x-lm-desired-account: " .. (desired_account ~= "" and desired_account or "<missing>"),
    "",
    "Proceed?",
  }, "\n")

  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

local function extract_http_body(raw)
  local lines = vim.split(raw or "", "\n", { plain = true })
  local last_sep = nil
  for i = 1, #lines do
    if lines[i] == "" then
      last_sep = i
    end
  end
  if not last_sep then
    return raw or ""
  end
  return table.concat(vim.list_slice(lines, last_sep + 1, #lines), "\n")
end

local function open_result_window(content)
  local split_dir = config.split.direction or "botright"
  local split_size = tonumber(config.split.size) or 16

  vim.cmd(string.format("%s %dsplit", split_dir, split_size))
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = "http"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "nvim-http://response")
end

local function write_history(request_name, request_text, response)
  local cwd = vim.fn.getcwd()
  local dir = cwd .. "/" .. config.history_dir
  ensure_dir(dir)

  local stamp = os.date("%Y%m%d-%H%M%S")
  local uv = vim.uv or vim.loop
  local uniq = tostring(uv.hrtime() % 1000000)
  local safe = sanitize_name(request_name)
  local path = string.format("%s/%s-%s-%s.http.response", dir, stamp, uniq, safe)

  local lines = {
    "# nvim-http response",
    "# request: " .. request_name,
    "# status: " .. response.status,
    "# time_total: " .. response.time_total,
    "# timestamp: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
    "",
    "## request",
  }
  append_multiline(lines, request_text)
  table.insert(lines, "")
  table.insert(lines, "## response")
  append_multiline(lines, response.raw)
  table.insert(lines, "")

  vim.fn.writefile(lines, path)

  return path
end

local function run_request_async(req, cb, opts)
  local include_headers = true
  if opts and opts.include_headers == false then
    include_headers = false
  end
  local args = build_curl_args(req, include_headers)
  local stdout = {}
  local stderr = {}

  local job = vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= nil then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= nil and line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local err_lines = {}
          for _, line in ipairs(stderr) do
            table.insert(err_lines, line)
          end
          if #err_lines == 0 then
            for _, line in ipairs(stdout) do
              table.insert(err_lines, line)
            end
          end
          cb(nil, "curl failed:\n" .. table.concat(err_lines, "\n"))
          return
        end

        local parsed = parse_curl_output(stdout)
        cb(parsed, nil)
      end)
    end,
  })

  if job <= 0 then
    cb(nil, "failed to start curl job")
  end
end

local function ensure_oauth_tokens_async(ctx, cb)
  local oauth = ctx.vars.oauth
  if type(oauth) ~= "table" then
    cb(true, nil)
    return
  end

  local token_url = oauth.token_url and interpolate(oauth.token_url, ctx.vars) or nil
  local username = oauth.username
  local password = oauth.password
  if not token_url or token_url == "" or not username or username == "" or not password or password == "" then
    cb(nil, "oauth config requires oauth.token_url, oauth.username and oauth.password")
    return
  end

  local cwd = vim.fn.getcwd()
  local cache_path = cwd .. "/" .. (config.oauth_cache_file or ".nvim-http.oauth-cache.json")
  local cache, cache_err = read_json_file(cache_path)
  if not cache then
    cb(nil, cache_err)
    return
  end

  local cache_key = oauth.cache_key or (token_url .. "|" .. username)
  local refresh_skew = tonumber(oauth.refresh_skew_seconds) or 60
  local now = os.time()
  local entry = cache[cache_key]
  if type(entry) == "table" then
    local expires_at = tonumber(entry.expires_at) or 0
    if entry.access_token and entry.id_token and (expires_at - refresh_skew) > now then
      ctx.vars.access_token = entry.access_token
      ctx.vars.id_token = entry.id_token
      ctx.vars.oauth_access_token = entry.access_token
      ctx.vars.oauth_id_token = entry.id_token
      cb(true, nil)
      return
    end
  end

  spinner.message = "Refreshing OAuth token..."
  local grant_type = oauth.grant_type or "password"
  local payload = {
    grant_type = grant_type,
    username = username,
    password = password,
  }
  if oauth.scope and oauth.scope ~= "" then
    payload.scope = oauth.scope
  end

  local body, encode_err = json_encode(payload)
  if not body then
    cb(nil, encode_err)
    return
  end

  local req = {
    method = "POST",
    url = token_url,
    headers = {
      { key = "Content-Type", value = "application/json" },
      { key = "Accept", value = "application/json" },
    },
    body = body,
  }

  run_request_async(req, function(parsed, run_err)
    if run_err then
      cb(nil, "oauth token request failed: " .. run_err)
      return
    end

    if tostring(parsed.status):sub(1, 1) ~= "2" then
      cb(nil, "oauth token request failed with status " .. tostring(parsed.status) .. ":\n" .. tostring(parsed.raw))
      return
    end

    local body_json = extract_http_body(parsed.raw)
    local decoded, decode_err = json_decode(body_json)
    if not decoded or type(decoded) ~= "table" then
      cb(nil, "oauth token response is not valid json: " .. tostring(decode_err))
      return
    end

    local access_token = decoded.access_token
    local id_token = decoded.id_token
    if not access_token or access_token == "" or not id_token or id_token == "" then
      cb(nil, "oauth token response missing access_token or id_token")
      return
    end

    local expires_in = tonumber(decoded.expires_in) or 86400
    local expires_at = now + expires_in
    cache[cache_key] = {
      access_token = access_token,
      id_token = id_token,
      expires_at = expires_at,
      expires_in = expires_in,
      username = username,
      token_url = token_url,
      updated_at = now,
    }
    local ok, write_err = write_json_file(cache_path, cache)
    if not ok then
      cb(nil, write_err)
      return
    end

    ctx.vars.access_token = access_token
    ctx.vars.id_token = id_token
    ctx.vars.oauth_access_token = access_token
    ctx.vars.oauth_id_token = id_token
    cb(true, nil)
  end, { include_headers = false })
end

local function run_sections_async(sections, done)
  local result_blocks = {}
  local merged_globals, vars_err = merged_vars()
  if not merged_globals then
    done(nil, vars_err)
    return
  end
  local ctx = { vars = merged_globals, last = nil }
  local total = #sections

  local function step(idx)
    if idx > total then
      done(table.concat(result_blocks, "\n"), nil)
      return
    end

    local section = sections[idx]
    if section.kind == "script" then
      local ok, err = run_lua_script(section, ctx)
      if not ok then
        done(nil, err)
        return
      end
      step(idx + 1)
    else
      local req, parse_err = parse_http_request(section.lines)
      if not req then
        done(nil, parse_err)
        return
      end

      req.url = interpolate(req.url, ctx.vars)
      apply_default_headers(req, ctx.vars)
      for _, h in ipairs(req.headers) do
        h.value = interpolate(h.value, ctx.vars)
      end
      req.body = interpolate(req.body, ctx.vars)
      if not confirm_non_get_request(req, ctx.vars) then
        done(nil, "request aborted by user")
        return
      end

      spinner.message = string.format("Running [%d/%d] %s", idx, total, section.name)
      run_request_async(req, function(parsed, run_err)
        if run_err then
          done(nil, "curl failed for " .. section.name .. ":\n" .. run_err)
          return
        end

        ctx.last = {
          section = section.name,
          request = req,
          response = parsed,
        }

        local req_txt = table.concat(section.lines, "\n")
        local history_path = write_history(section.name, req_txt, parsed)

        table.insert(result_blocks, string.format("### %s", section.name))
        table.insert(result_blocks, "status: " .. parsed.status .. "  time_total: " .. parsed.time_total .. "s")
        table.insert(result_blocks, "history: " .. history_path)
        table.insert(result_blocks, "")
        table.insert(result_blocks, parsed.raw)
        table.insert(result_blocks, "")

        step(idx + 1)
      end)
    end
  end

  ensure_oauth_tokens_async(ctx, function(_, oauth_err)
    if oauth_err then
      done(nil, oauth_err)
      return
    end
    step(1)
  end)
end

local function run(scope)
  local bufnr = vim.api.nvim_get_current_buf()
  local sections = parse_sections(bufnr)
  if #sections == 0 then
    vim.notify("No requests found", vim.log.levels.WARN)
    return
  end

  local selected = sections
  if scope == "cursor" then
    local sec = section_at_cursor(sections)
    if not sec then
      vim.notify("No request at cursor", vim.log.levels.WARN)
      return
    end

    if sec.kind == "script" then
      vim.notify("Cursor is inside script section; place cursor in a request section", vim.log.levels.WARN)
      return
    end

    selected = {}
    for _, candidate in ipairs(sections) do
      if candidate.start_line <= sec.ending_line then
        table.insert(selected, candidate)
      end
      if candidate == sec then
        break
      end
    end
  end

  local vars, vars_err = merged_vars()
  if not vars then
    vim.notify(vars_err, vim.log.levels.ERROR)
    return
  end
  sync_desired_account_global(vars)

  spinner_start("Running requests...")
  run_sections_async(selected, function(output, err)
    spinner_stop()
    if not output then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    open_result_window(output)
  end)
end

function M.run_current()
  run("cursor")
end

function M.run_all()
  run("all")
end

function M.current_desired_account()
  local value, _ = refresh_desired_account_global()
  return value or ""
end

function M.setup(opts)
  merge(config, opts or {})
  refresh_desired_account_global()

  if not augroup_id then
    augroup_id = vim.api.nvim_create_augroup("NvimHttpStatus", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
      group = augroup_id,
      pattern = "*.http",
      callback = function()
        refresh_desired_account_global()
      end,
    })
    vim.api.nvim_create_autocmd({ "DirChanged" }, {
      group = augroup_id,
      callback = function()
        refresh_desired_account_global()
      end,
    })
  end

  if not commands_created then
    vim.api.nvim_create_user_command("HttpRun", function()
      M.run_current()
    end, { desc = "Run .http requests up to cursor" })

    vim.api.nvim_create_user_command("HttpRunAll", function()
      M.run_all()
    end, { desc = "Run all .http requests" })

    vim.api.nvim_create_user_command("HttpHistory", function()
      local dir = vim.fn.getcwd() .. "/" .. config.history_dir
      ensure_dir(dir)
      vim.cmd("edit " .. vim.fn.fnameescape(dir))
    end, { desc = "Open nvim-http history directory" })

    vim.api.nvim_create_user_command("HttpPickDesiredAccount", function()
      local vars, err = merged_vars()
      if not vars then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      local items = vars.desired_accounts
      if type(items) ~= "table" or #items == 0 then
        vim.notify("No desired_accounts list found in vars", vim.log.levels.WARN)
        return
      end
      vim.ui.select(items, { prompt = "Select x-lm-desired-account" }, function(choice)
        if not choice or choice == "" then
          return
        end
        session_overrides.desired_account = choice
        sync_desired_account_global({ desired_account = choice })
        vim.cmd("redrawstatus")
        vim.notify("desired_account set to " .. choice, vim.log.levels.INFO)
      end)
    end, { desc = "Pick desired account for current Neovim session" })

    vim.api.nvim_create_user_command("HttpCurrentDesiredAccount", function()
      local vars, err = merged_vars()
      if not vars then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      sync_desired_account_global(vars)
      vim.cmd("redrawstatus")
      local acc = current_desired_account(vars)
      if acc == "" then
        vim.notify("desired_account is not set", vim.log.levels.WARN)
        return
      end
      vim.notify("current desired_account: " .. acc, vim.log.levels.INFO)
    end, { desc = "Show current desired account" })
    commands_created = true
  end
end

return M
