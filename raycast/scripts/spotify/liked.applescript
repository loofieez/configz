#!/usr/bin/osascript

# raycast script-command for spotify
# play `liked songs` collection on spotify

# required parameters:
# @raycast.schemaVersion 1
# @raycast.mode "silent"
# @raycast.title "play liked songs"

# optional parameters:
# @raycast.packageName "spotify"
# @raycast.icon "images/spotify.png"

# documentation:
# @raycast.author "loofieez"
# @raycast.authorURL "https://github.com/loofieez"
# @raycast.description "play liked songs collection on spotify"

on run
    # set system volume to 75
    set volume output volume 75
    # main block, for script
    tell application "Spotify"
        # set spotify volume
        set sound volume to 75
        # turn off shuffling
        set shuffling to false
        # set your playlist uri
        play track "spotify:user:31kymx7zaanvvsbik7aecl53vgom:collection"
    end tell

    # a small hack to hide spotify
    # after successful execution
    tell application "System Events"
        set visible of process "Spotify" to false
    end tell

    # waiting
    delay 2.5

    # log, and alert about execution
    return "Playing, Liked Songs! Collection."
end run
