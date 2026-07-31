#!/usr/bin/osascript

# raycast script-command for spotify
# check what songs are playing on `spotify`

# required parameters:
# @raycast.schemaVersion 1
# @raycast.mode "silent"
# @raycast.title "now playing"

# optional parameters:
# @raycast.packageName "spotify"
# @raycast.icon "images/spotify.png"

# documentation:
# @raycast.author "loofieez"
# @raycast.authorURL "https://github.com/loofieez"
# @raycast.description "what's playing currently on spotify"

on run
    # check if spotify is running
    tell application "System Events"
        set isSpotifyRunning to (exists process "Spotify")
    end tell

    # if not running, return an error
    if not isSpotifyRunning then
        return "Spotify is Not Open"
    end if

    # main block
    tell application "Spotify"
        # get player state and track info
        set playerState to player state
        set currentTrack to current track
        set trackName to name of currentTrack
        set artistName to artist of currentTrack

        # determine status text
        if playerState is playing then
            set statusText to "Playing: "
        else if playerState is paused then
            set statusText to "Paused"
        else if playerState is stopped then
            set statusText to "Stopped"
        else
            set statusText to "Unknown Status"
        end if

        # waiting
        delay 2.5

        # format output
        return statusText & trackName & " by " & artistName
    end tell
end run
