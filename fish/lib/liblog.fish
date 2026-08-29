#!/usr/bin/env fish

# ~/.config/fish/lib/liblog.fish
# reusable stderr-only logger (generic)

# validate: fish --no-execute liblog.fish
# format: fish_indent --write liblog.fish

# source (do not autoload by function name):
#   source ~/.config/fish/lib/liblog.fish

# env:
#   LOG_LEVEL    trace|debug|info|warn|error|fatal|silent  (default: debug)
#   LOG_PREFIX   logger name (default: log)
#   LOG_COLOR    auto|always|never                         (default: auto)
#   LOG_QUIET    1 = errors/fatal only

# example:
#   set --global --export LOG_PREFIX myscript
#   log_info "starting"
#   log_error "failed"; return 1
#   log_fatal "cannot continue"   # prints + returns 1

# reload in a live shell:
#   set --export LIBLOG_RELOAD 1
#   source ~/.config/fish/lib/liblog.fish

if set --query __LIBLOG_LOADED
    if not set --query LIBLOG_RELOAD
        exit 0
    end
end

set --global __LIBLOG_LOADED 1

# map level name to number
# levels (numeric, lower = more verbose):
#   trace=0 debug=1 info=2 warn=3 error=4 fatal=5 silent=6
# a line is printed only if its number >= LOG_LEVEL's number.
# example: LOG_LEVEL=warn hides trace/debug/info.
function __liblog_level_num --description 'map level name to number'
    switch (string lower -- $argv[1])
        case trace
            echo 0
        case debug
            echo 1
        case info
            echo 2
        case warn warning
            echo 3
        case error
            echo 4
        case fatal
            echo 5
        case silent quiet
            echo 6
        case '*'
            echo 1
    end
end

# auto (default): color only when stderr is a TTY (not when piped/redirected)
# always / never: force regardless of TTY
function __liblog_color_enabled --description 'true if log colors should be used'
    set --local mode auto

    if set --query LOG_COLOR
        set mode (string lower -- $LOG_COLOR)
    end

    switch $mode
        case always yes 1 true
            return 0

        case never no 0 false
            return 1

        case '*'
            isatty stderr
            return $status
    end
end

# defense in depth: even if a caller accidentally logs a key/token, strip
# common patterns. This is NOT a substitute for never logging file contents.
# patterns:
#   AGE-SECRET-KEY-...     age identity
#   PEM private key block  RSA/ed25519/etc
#   ops_...                1Password service-account tokens
#   eyJ... JWT             three-segment JWTs
function __liblog_redact --description 'strip common secret patterns from a log line'
    set --local s $argv

    set s (string replace --regex --all -- 'AGE-SECRET-KEY-[A-Z0-9-]+' 'AGE-SECRET-KEY-[REDACTED]' $s)
    set s (string replace --regex --all -- '-----BEGIN[A-Z ]*PRIVATE KEY-----.*?-----END[A-Z ]*PRIVATE KEY-----' '[REDACTED-PEM]' $s)
    set s (string replace --regex --all -- 'ops_[A-Za-z0-9_-]+' 'ops_[REDACTED]' $s)
    set s (string replace --regex --all -- 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' '[REDACTED-JWT]' $s)

    printf '%s' $s
end

# local timestamp
function __liblog_ts --description 'local timestamp'
    date '+%Y-%m-%d %H:%M:%S'
end

# core logger: __liblog_write LEVEL message...
function __liblog_write --description 'core logger: __liblog_write LEVEL message...'
    set --local level (string lower -- $argv[1])
    set --erase argv[1]
    set --local msg (string join -- ' ' $argv)

    # LOG_QUIET=1: drop everything except error/fatal (CI / -q)
    if set --query LOG_QUIET; and test "$LOG_QUIET" != 0
        switch $level
            case error fatal
                true

            case '*'
                return 0
        end
    end

    set --local min debug

    if set --query LOG_LEVEL
        set min $LOG_LEVEL
    end

    set --local have (__liblog_level_num $level)
    set --local need (__liblog_level_num $min)

    if test $have -lt $need
        return 0
    end

    set --local prefix log
    if set --query LOG_PREFIX
        set prefix $LOG_PREFIX
    end

    set --local lvl (string upper -- $level)
    set --local line (__liblog_redact $msg)

    # colored: dim timestamp + prefix, bold level, color by severity
    # always `>&2` so `sopsx decrypt f.yaml > out` never mixes logs into out.
    if __liblog_color_enabled
        set --local reset \e'[0m'
        set --local bold \e'[1m'
        set --local dim \e'[2m'
        set --local col $reset

        switch $level
            case trace
                set col \e'[90m'
            case debug
                set col \e'[36m'
            case info
                set col \e'[32m'
            case warn warning
                set col \e'[33m'
            case error
                set col \e'[31m'
            case fatal
                set col \e'[91m'
            case success
                set col \e'[32m'
        end

        printf '%s%s%s %s[%s]%-5s%s %s[%s]%s %s%s\n' \
            $dim (__liblog_ts) $reset \
            $col $bold $lvl $reset \
            $dim $prefix $reset \
            $line \
            >&2
    else
        printf '%s [%s] [%s] %s\n' (__liblog_ts) $lvl $prefix $line >&2
    end

    if test $level = fatal
        return 1
    end

    return 0
end

function log_trace
    __liblog_write trace $argv
end

function log_debug
    __liblog_write debug $argv
end

function log_info
    __liblog_write info $argv
end

function log_warn
    __liblog_write warn $argv
end

function log_error
    __liblog_write error $argv
end

function log_fatal
    __liblog_write fatal $argv
    return 1
end

function log_success
    # success is an info-level event with a friendly name for call sites.
    __liblog_write info $argv
end