#!/usr/bin/env fish

# ~/.config/fish/conf.d/c-source.fish
# evals, sources, etc like func. can be found here.

if status is-interactive
    # source zoxide in fish
    zoxide init fish | source
end
