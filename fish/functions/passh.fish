#!/usr/bin/env fish

# ~/.config/fish/functions/passh.fish
# smol wrapper for ssh with `proton-pass`
# idea was to implement `ssh-agent` with `proton-pass-cli`
# so, implemented a lazy-loaded function in secure way to connect ssh, and workaround for git!

# main function
function passh --description "authenticate ssh with proton-pass"

    # parse cli-flags for this func
    argparse 'start' 'stop' 'help' -- $argv
    or return 1

    # set proton-pass sock variables
    set --local sock_dir "$HOME/.ppass"
    set --local ppass_sock "$sock_dir/agent.sock"

    # custom function for logging messages
    function _log --description "function for logging messages"
        set --local lvl "info"
        set --local msg ""

        switch $argv[1]
            case info warn debug error
                set lvl $argv[1]
                set msg $argv[2..-1]
            case '*'
                set msg $argv
        end

        # gum log with structured logging
        gum log --structured --time rfc822 --level $lvl $msg
    end

    # for `passh -stop`
    if set --query --local _flag_stop
        _log info "initiating shutdown function for proton-pass agent."

        # check if pass-cli daemon is running or not
        if pgrep -f "pass-cli ssh-agent" > /dev/null
            pkill -f "pass-cli ssh-agent"
            _log info "proton-pass agent daemon terminated."
        else
            _log warn "proton-pass agent was not running!"
        end

        # remove pass-cli socket
        if test -e $ppass_sock
            rm -rf $ppass_sock
            _log info "proton-pass socket removed successfully."
        end

        # set previous apple listener for ssh socket
        set --local apple_sock (launchctl getenv SSH_AUTH_SOCK)

        # check if socket exists
        if test -n "$apple_sock"
            # export as global variable
            set --global --export SSH_AUTH_SOCK $apple_sock
            _log info "restored macOS default launchd listener."

            # remove/delete all keys from ssh-agent
            ssh-add -D >/dev/null 2>&1
            _log info "flushed all loaded keys from macOS native ssh-agent."
        else
            set --erase SSH_AUTH_SOCK
            _log warn "could not fetch apple listener path."
        end

        # remove orphaned_sockets, or zombies sockets from ssh dir
        set --local orphaned_sockets (fd --type socket --hidden . $HOME/.ssh 2>/dev/null)
        if test -n "$orphaned_sockets"
            fd --type socket --hidden . $HOME/.ssh --exec rm -rf
            _log info "wiped orphaned ssh sockets from ~/.ssh dir."
        else
            _log warn "no orphaned sockets found in ~/.ssh dir."
        end
    end

    # for `pass -start`
    if set --query --local _flag_start
        _log info "initiating proton-pass ssh environment."

        if not test -d $sock_dir
            _log warn "socket dir is not created, please create and check."
        end

        # check if proton agent is running or not
        if pgrep -f "pass-cli ssh-agent" >/dev/null; and test -S $ppass_sock
            _log info "proton agent is already running. please, reuse this proc."
        else
            rm -rf $ppass_sock
            # start `pass-cli` with vault `dev`
            pass-cli ssh-agent start --vault-name dev --socket-path $ppass_sock > /dev/null 2>&1 &

            set --local timeout 5
            # check if, pass-cli is connecting or not
            while not test -S $ppass_sock
                if test $timeout -le 0
                    _log error "agent socket timeout. did you run `pass-cli login`?"
                    functions --erase _log
                    return 1
                end
                sleep 1
                set timeout (math $timeout - 1)
            end

            _log info "proton-pass daemon started, & socket attached."
        end

        # export socket exposed from `pass-cli`
        set --global --export SSH_AUTH_SOCK $ppass_sock
        _log info "exported SSH_AUTH_SOCK to proton agent."

        _log info "testing github ssh authentication ..."
        # check if sshing in github is working fine or not
        if ssh -T git@github.com 2>&1 | rg --quiet "successfully authenticated"
            _log info "github authentication verified successfully!"
        else
            _log error "github authentication could not be verified!"
            functions --erase _log
            return 1
        end
    end

    # erase helper func. from memory
    functions --erase _log
end
