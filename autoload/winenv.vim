" Edit global environment variable on MS Windows.
" Version: 1.0
" Author : thinca <thinca+vim@gmail.com>
" License: zlib License

let s:save_cpo = &cpo
set cpo&vim


let g:winenv#opener = get(g:, 'editvar#opener', 'new')
let g:winenv#default_place = get(g:, 'g:winenv#default_place', 'SYSTEM')

let s:winenv_cmd = expand('<sfile>:p:h:h') . '\bin\winenv.bat'

" XXX: to be configuable?
let s:separators = {
\   'PATH': ';',
\   'PATHEXT': ';',
\ }

function! s:run(args, ...)
  let cmd = join(map([s:winenv_cmd] + a:args, 'shellescape(v:val)'), ' ')
  let result = a:0 == 0 ? system(cmd) : system(cmd, a:1)
  return iconv(result, &termencoding, &encoding)
endfunction

function! winenv#places()
  if !exists('s:places')
    let s:places = split(s:run(['--places']), "\n")
  endif
  return s:places
endfunction

function! winenv#list(place)
  return split(s:run(['--place', a:place, '--list']), "\n")
endfunction

function! winenv#names(place)
  return split(s:run(['--place', a:place, '--names']), "\n")
endfunction

function! winenv#get(place, name)
  return s:run(['--place', a:place, '--', a:name])
endfunction

function! winenv#set(place, name, value)
  return s:run(['--place', a:place, '--file', '-', '--', a:name] , a:value)
endfunction

function! winenv#remove(place, name)
  return s:run(['--place', a:place, '--remove', '--', a:name])
endfunction


function! winenv#_read(path)
  let path_data = s:parse_path(a:path)
  let modifiable = 0
  nmapclear <buffer>
  if empty(path_data.place)
    let b:winenv_buftype = 'place'
    let content = winenv#places()
    nmap <buffer> <CR> <Plug>(winenv-edit)
  elseif empty(path_data.var_name)
    let b:winenv_buftype = 'list'
    let content = winenv#names(path_data.place)
    nmap <buffer> <CR> <Plug>(winenv-edit)
  else
    let b:winenv_buftype = 'variable'
    let content = winenv#get(path_data.place, path_data.var_name)
    let var_key = toupper(path_data.var_name)
    if has_key(s:separators, var_key)
      let separator = s:separators[var_key]
      let b:winenv_separator = separator
      let l:.content = split(content, separator)
    endif
    let modifiable = 1
  endif
  setlocal modifiable
  silent put =content
  silent 1 delete _
  setlocal buftype=acwrite
  setlocal nomodified
  let &l:modifiable = modifiable
endfunction

function! winenv#_write(path)
  let path_data = s:parse_path(a:path)
  if empty(path_data.place) || empty(path_data.var_name)
    return
  endif

  let lines = getline(1, '$')
  let content = exists('b:winenv_separator') ?
  \             join(lines, b:winenv_separator) : join(lines, "\n")

  if empty(content)
    call winenv#remove(path_data.place, path_data.var_name)
    execute 'let $' . path_data.var_name . ' = ""'
  else
    call winenv#set(path_data.place, path_data.var_name, content)
    execute 'let $' . path_data.var_name . ' = content'
  endif
  setlocal nomodified
endfunction

function! winenv#_edit()
  let path_data = s:parse_path(bufname('%'))
  if empty(path_data.place)
    let path_data.place = getline('.')
  else
    let path_data.var_name = getline('.')
  endif
  call s:open(path_data.place, path_data.var_name, 'edit')
endfunction

function! s:parse_path(path)
  let list = matchlist(a:path, '^\vwinenv:[\\/]{2}%((\w+)%([\\/](.+))?)?$')
  return {'place': get(list, 1, ''), 'var_name': get(list, 2, '')}
endfunction

function! s:open(place, var_name, opener)
  let args = a:place
  if !empty(a:var_name)
    let args .= '/' . a:var_name
  endif
  execute a:opener '`="winenv://" . args`'
endfunction

function! winenv#open(...)
  let place = get(a:000, 0, '')
  let var_name = get(a:000, 1, '')
  call s:open(place, var_name, g:winenv#opener)
endfunction

function! winenv#command(args)
  let [place, name] =
  \ a:args ==# ''  ? ['', ''] :
  \ a:args =~# '/' ? split(a:args, '/', 1)[0 : 1] :
  \                  [g:winenv#default_place, a:args]
  call winenv#open(place, name)
endfunction

function! winenv#complete(lead, cmd, pos)
  if a:lead =~# '/'
    let place = matchstr(a:lead, '^\w\+\ze/')
    let list = map(winenv#names(place), 'place . "/" . v:val')
  else
    let list = map(copy(winenv#places()), 'v:val . "/"') +
    \          winenv#names(g:winenv#default_place)
  endif
  return filter(list, 'v:val =~? "^" . a:lead')
endfunction


let &cpo = s:save_cpo
unlet s:save_cpo
