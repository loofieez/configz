#!/usr/bin/env fish

# ~/.config/fish/lib/libsopsx.fish
# helper function for sopsx specifically

# validate: fish --no-execute libsopsx.fish
# format: fish_indent --write libsopsx.fish

# source trap
if set --query __LIBSOPSX_LOADED
    if not set --query LIBSOPSX_RELOAD
        exit 0
    end
end

set --global __LIBSOPSX_LOADED 1

# print octal permission bits for a path
function __sopsx_file_mode --description 'print octal permission bits for a path'
    set --local p $argv[1]

    switch (uname -s)
        case Darwin
            stat -f %Lp -- $p

        case '*'
            stat --format %a -- $p
    end
end

# print file size in bytes for a path
function __sopsx_file_size --description 'print file size in bytes for a path'
    set --local p $argv[1]

    switch (uname -s)
        case Darwin
            stat -f %z -- $p

        case '*'
            stat --format %s -- $p
    end
end

# print file owner name for a path
function __sopsx_file_owner --description 'print file owner name for a path'
    set --local p $argv[1]

    switch (uname -s)
        case Darwin
            stat -f %Su -- $p

        case '*'
            stat --format %U -- $p
    end
end

# log metadata for a path (never contents)
# safe to call on secret files: mode/size/owner only.
function dbg_file_info --description 'log metadata for a path (never contents)'
    dbg_enabled; or return 0
    set --local p $argv[1]

    if test -z "$p"
        __liblog_write debug "file: (empty path)"
        return 0
    end

    if not test -e $p
        __liblog_write debug "file: $p (does not exist)"
        return 0
    end

    set --local kind unknown

    if test -L $p
        set kind symlink
    else if test -d $p
        set kind directory
    else if test -f $p
        set kind file
    else if test -p $p
        set kind fifo
    end

    set --local mode (__sopsx_file_mode $p 2>/dev/null)
    set --local size (__sopsx_file_size $p 2>/dev/null)
    set --local owner (__sopsx_file_owner $p 2>/dev/null)
    __liblog_write debug "file path=$p kind=$kind mode=$mode size=$size owner=$owner"
end

# printed at the start of encrypt/decrypt/doctor so a bug report has context.
# warns if SOPS_AGE_KEY / SOPS_AGE_KEY_FILE are set (unsafe vs KEY_CMD).
function dbg_banner --description 'dump non-secret runtime context'
    dbg_enabled; or return 0
    __liblog_write debug "── debug context ──"

    dbg_kv fish_version $FISH_VERSION
    dbg_kv pwd (pwd)
    dbg_kv user (whoami)
    dbg_kv umask (umask)
    dbg_kv tmpdir (__sopsx_tmpdir)
    dbg_kv SOPS_AGE_KEY_CMD (set --query SOPS_AGE_KEY_CMD; and echo $SOPS_AGE_KEY_CMD; or echo '')

    dbg_kv SOPS_AGE_RECIPIENTS (set --query SOPS_AGE_RECIPIENTS; and echo $SOPS_AGE_RECIPIENTS; or echo '')

    if set --query SOPS_AGE_KEY
        log_warn "SOPS_AGE_KEY is set in the environment (prefer SOPS_AGE_KEY_CMD; key material in env is unsafe)"
    end

    if set --query SOPS_AGE_KEY_FILE
        dbg_kv SOPS_AGE_KEY_FILE $SOPS_AGE_KEY_FILE
        log_warn "SOPS_AGE_KEY_FILE is set; SOPS_AGE_KEY_CMD is the preferred op path"
    end

    __liblog_write debug "── end context ──"
end