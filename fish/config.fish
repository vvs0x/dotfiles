fzf --fish | source
zoxide init fish | source

set -g __fish_git_prompt_showdirtystate 1
set -g __fish_git_prompt_showuntrackedfiles 1
set -g __fish_git_prompt_char_dirtystate '*'
set -g __fish_git_prompt_char_untrackedfiles '?'
set -g fish_autosuggestion_enabled 1
set -gx EDITOR nvim
