#!/usr/bin/env fish

# small wrapper for `sops, and age` with `proton-pass`
# idea was to create a wrapper to fetch `age-keys` from `proton-pass` via `proton-pass cli`
# so created, a small lazy-loaded function to pull those `age-keys` and save it in RAM for temporary access.
# it'll create a volume, mount it, and then save it. once, I triggered `sops` command it will unmount that volume.

# main function
function sopsx --description "fetch age-keys from proton-pass cli"

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



    # verify `proton-pass` session
    if not pass-cli test >/dev/null 2>&1
        _log error "proton-pass session expired, please login or unlock the session!"
        return 1
    end

    # extract keys purely into memory variables, filtering strictly for the secret key
    set --local key1 (pass-cli item view "pass://dev/age_git/age_priv1" | string trim)
    set --local key2 (pass-cli item view "pass://dev/age_git/age_priv2" | string trim)
    set --local key3 (pass-cli item view "pass://dev/age_git/age_priv3" | string trim)
    set --local key4 (pass-cli item view "pass://dev/age_git/age_priv4" | string trim)
    set --local key5 (pass-cli item view "pass://dev/age_git/age_priv5" | string trim)
    _log info "exported age-keys from proton-pass cli."

    # check if exported keys are valid or not
    if test -z "$key1"; or test -z "$key2"; or test -z "$key3"; or test -z "$key4"; or test -z "$key5"
        _log error "exported keys are not valid, please check fields of proton-pass!"
        return 1
    end

    # allocate a tiny 2MB virtual drive strictly in your mac's RAM
    set --local ram_dev (hdiutil attach -nomount ram://4096 | string trim)
    _log info "allocated 2MB of virtual drive in mac's RAM."

    # check if allocated RAM is there or not
    if test -z "$ram_dev"
        _log error "please, check RAM is not allocated in mac's disk!"
        return 1
    end

    # format and mount it securely
    diskutil erasevolume HFS+ "SOPS_RAM" $ram_dev >/dev/null 2>&1
    _log info "SOPS_RAM mounted successfully."

    # guarantee the RAM disk is destroyed on `Exit, Error, or Ctrl+C`
    trap "hdiutil detach $ram_dev -force -quiet >/dev/null 2>&1" EXIT INT TERM
    set --local secure_key_path "/Volumes/SOPS_RAM/age-keys.txt"

    # write keys to mounted volume
    echo "$key1" > "$secure_key_path"
    echo "$key2" > "$secure_key_path"
    echo "$key3" > "$secure_key_path"
    echo "$key4" > "$secure_key_path"
    echo "$key5" > "$secure_key_path"
    _log info "keys written to mounted volume: SOPS_RAM"

    # set SOPS_AGE_KEY_FILE variable and execute sops
    set --local --export SOPS_AGE_KEY_FILE "$secure_key_path"
    sops decrypt --in-place $argv
    set --local sops_status $status
    _log info "hurray: sops decrypted your file, please check it."

    # check if an orphaned `SOPS_RAM` volume exists and purge it
    if test -d /Volumes/SOPS_RAM
        hdiutil detach /Volumes/SOPS_RAM -force >/dev/null 2>&1
        _log warn "purging orphaned SOPS_RAM volume."
    end

    # fail-safe: trap automatically cleans up the mounted volume upon exit.
    return $sops_status
end
