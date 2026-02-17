if exists("b:current_syntax")
  finish
endif

syntax case match

syntax match nvimHttpComment /^\s*\/\/.*$/
syntax match nvimHttpComment /^\s*#\%(##\)\@!.*$/

syntax match nvimHttpSection /^\s*###\s.*$/
syntax match nvimHttpScriptMarker /^\s*@script\s\+lua\s*$/

syntax match nvimHttpRequestLine /^\s*[A-Z]\+\s\+\S\+\s*$/ contains=nvimHttpMethod,nvimHttpUrl
syntax match nvimHttpMethod /^\s*\zs[A-Z]\+\ze\s\+\S\+/ contained
syntax match nvimHttpUrl /\s\+\zs\S\+\ze\s*$/ contained

syntax match nvimHttpQueryParam /^\s*[?&].*$/

syntax match nvimHttpHeader /^\s*[-A-Za-z0-9_]\+:\s*.*$/ contains=nvimHttpHeaderName,nvimHttpHeaderValue
syntax match nvimHttpHeaderName /^\s*\zs[-A-Za-z0-9_]\+\ze:/ contained
syntax match nvimHttpHeaderValue /:\s*\zs.*$/ contained

syntax match nvimHttpStatusLine /^\s*HTTP\/\d\+\%(\.\d\+\)\?\s\+\d\+\%(\s\+.*\)\?$/ contains=nvimHttpHttpVersion,nvimHttpStatusCode
syntax match nvimHttpHttpVersion /HTTP\/\d\+\%(\.\d\+\)\?/ contained
syntax match nvimHttpStatusCode /\s\zs\d\{3}\ze\%(\s\|$\)/ contained

syntax match nvimHttpMeta /^\s*status:\s.*$/
syntax match nvimHttpMeta /^\s*history:\s.*$/
syntax match nvimHttpVariable /{{\s*[A-Za-z0-9_.-]\+\s*}}/ containedin=ALL

syntax include @nvimHttpLua syntax/lua.vim
syntax region nvimHttpLuaBlock start=/^\s*@script\s\+lua\s*$/ end=/^\s*###\s\|\%$/me=s-1 keepend contains=nvimHttpScriptMarker,@nvimHttpLua

highlight default link nvimHttpSection Title
highlight default link nvimHttpScriptMarker PreProc
highlight default link nvimHttpComment Comment
highlight default link nvimHttpRequestLine Normal
highlight default link nvimHttpMethod Statement
highlight default link nvimHttpUrl Underlined
highlight default link nvimHttpQueryParam String
highlight default link nvimHttpHeaderName Type
highlight default link nvimHttpHeaderValue String
highlight default link nvimHttpStatusLine Constant
highlight default link nvimHttpHttpVersion Special
highlight default link nvimHttpStatusCode Number
highlight default link nvimHttpMeta Identifier
highlight default link nvimHttpVariable Special

let b:current_syntax = "http"
