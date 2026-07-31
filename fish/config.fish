# ~/.config/fish/config.fish
# minimal startup config for fish

# remove `fish_greeting`
if status is-interactive
    set --global fish_greeting
end

# set `catppuccin-frappe` theme
fish_config theme choose catppuccin-frappe
