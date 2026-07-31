#/usr/bin/env fish

# ~/.config/fish/conf.d/b-abbrv.fish
# bunch of abbreviations for most-used commands

if status is-interactive
    # development abbrv.
    abbr --add "v" "nvim"
    abbr --add "n" "nvim"

    # utilities abbrv.
    abbr --add "rmf" "rm -rfv"
    abbr --add "rmi" "rm -rfi"
    abbr --add "hic" "history clear"

    # few more abbrv.
    abbr --add "ze" "zoxide edit"
    abbr --add "zq" "zoxide query --list --score"
    abbr --add "bl" "brew list --versions"
    abbr --add "bi" "brew install % --ask --verbose"
end
