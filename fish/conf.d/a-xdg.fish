#!/usr/bin/env fish

# ~/.config/fish/conf.d/a-xdg.fish
# config for exported paths or variables.

# erase user-added paths
# set --erase fish_user_paths

# check `brew shellenv`
# exported variables for homebrew
set --global --export HOMEBREW_PREFIX "/opt/homebrew"
set --global --export HOMEBREW_CELLAR "/opt/homebrew/Cellar"
set --global --export HOMEBREW_REPOSITORY "/opt/homebrew"

# default variables
set --global --export XDG_CACHE_HOME "$HOME/.cache"
set --global --export XDG_CONFIG_HOME "$HOME/.config"
set --global --export XDG_DATA_HOME "$HOME/.local/share"

# exported variables for code, and lang.
set --global --export GOROOT "$HOME/.goroot"
set --global --export GOHOME "$HOME/.gopath"

# exported variables for utils
set --global --export EDITOR "nvim"
set --global --export MANPAGER "nvim +Man!"

# exported variables for zoxide
set --global --export _ZO_EXCLUDE_PATHS ".git"
set --global --export _ZO_DATA_DIR "$XDG_DATA_HOME/zoxide"