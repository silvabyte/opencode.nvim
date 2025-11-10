" opencode.nvim - AI-powered autocompletion using OpenCode
" Maintainer: OpenCode Team
" License: MIT

if exists('g:loaded_opencode')
  finish
endif
let g:loaded_opencode = 1

" Save user's cpoptions
let s:save_cpo = &cpo
set cpo&vim

" User commands
command! OpenCodeStart lua require('opencode').server.start()
command! OpenCodeStop lua require('opencode').server.stop()
command! OpenCodeStatus lua print(require('opencode').status())
command! OpenCodeToggle lua require('opencode').toggle()
command! OpenCodeSessionNew lua require('opencode').session.create_new()
command! OpenCodeSessionList lua require('opencode').session.list()
command! OpenCodeAcceptSuggestion lua require('opencode').accept_suggestion()
command! OpenCodeDismissSuggestion lua require('opencode').dismiss_suggestion()

" Default keymaps (can be disabled with g:opencode_disable_default_keymaps)
if !exists('g:opencode_disable_default_keymaps') || !g:opencode_disable_default_keymaps
  " Insert mode - accept suggestion with Tab (if available)
  inoremap <expr> <silent> <Tab> luaeval("require('opencode').has_suggestion()") ? "<Cmd>OpenCodeAcceptSuggestion<CR>" : "<Tab>"

  " Insert mode - request completion manually
  inoremap <silent> <C-]> <Cmd>lua require('opencode').request_completion()<CR>

  " Normal mode - toggle
  nnoremap <silent> <leader>oc <Cmd>OpenCodeToggle<CR>

  " Normal mode - status
  nnoremap <silent> <leader>os <Cmd>OpenCodeStatus<CR>
endif

" Restore cpoptions
let &cpo = s:save_cpo
unlet s:save_cpo
