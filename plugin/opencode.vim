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
command! OpenCodeComplete lua require('opencode').request_completion()
command! OpenCodeAccept lua require('opencode').accept_suggestion()
command! OpenCodeAcceptWord lua require('opencode').accept_word()
command! OpenCodeAcceptLine lua require('opencode').accept_line()
command! OpenCodeDismiss lua require('opencode').dismiss_suggestion()
command! OpenCodeClearCache lua require('opencode').clear_cache()
command! OpenCodeReset lua require('opencode').reset()

" Legacy command aliases for backwards compatibility
command! OpenCodeAcceptSuggestion lua require('opencode').accept_suggestion()
command! OpenCodeDismissSuggestion lua require('opencode').dismiss_suggestion()

" Default keymaps (can be disabled with g:opencode_disable_default_keymaps)
" Note: Most keymaps are now set up in the completion module for better integration
if !exists('g:opencode_disable_default_keymaps') || !g:opencode_disable_default_keymaps
  " Normal mode - toggle
  nnoremap <silent> <leader>oc <Cmd>OpenCodeToggle<CR>

  " Normal mode - status
  nnoremap <silent> <leader>os <Cmd>OpenCodeStatus<CR>

  " Normal mode - clear cache
  nnoremap <silent> <leader>ox <Cmd>OpenCodeClearCache<CR>
endif

" Restore cpoptions
let &cpo = s:save_cpo
unlet s:save_cpo
