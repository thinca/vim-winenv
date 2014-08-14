" Edit global environment variable on MS Windows.
" Version: 1.0
" Author : thinca <thinca+vim@gmail.com>
" License: zlib License

if !has('win32')
  finish
endif

if exists('g:loaded_winenv')
  finish
endif
let g:loaded_winenv = 1

let s:save_cpo = &cpo
set cpo&vim


command! -nargs=* -complete=customlist,winenv#complete
\        WinEnv call winenv#command(<q-args>)

nnoremap <silent> <Plug>(winenv-edit) :<C-u>call winenv#_edit()<CR>

augroup plugin-winenv
  autocmd!
  autocmd BufReadCmd  winenv://* call winenv#_read(expand('<amatch>'))
  autocmd BufWriteCmd winenv://* call winenv#_write(expand('<amatch>'))
augroup END


let &cpo = s:save_cpo
unlet s:save_cpo
