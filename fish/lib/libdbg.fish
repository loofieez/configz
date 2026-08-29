#!/usr/bin/env fish

# ~/.config/fish/lib/libdbg.fish
# reusable debug helpers (generic; requires liblog)

# validate: fish --no-execute libdbg.fish
# format: fish_indent --write libdbg.fish

# source after liblog:
#   source ~/.config/fish/lib/liblog.fish
#   source ~/.config/fish/lib/libdbg.fish

# env:
#   DBG_ENABLED  1/0  (default: 1)
#   DBG_TRACE    1    extra tracing

# example:
#   dbg_kv pwd (pwd)
#   dbg_cmd command ls -l
#   dbg_check "git present" command -q git; or return 1
#   dbg_timer_start work; ...; dbg_timer_end work

# secret-looking keys (*key* *token* *secret* *password*) are always redacted.
# to log a non-secret command string whose name contains "key", use dbg_print:
#   dbg_print "SOPS_AGE_KEY_CMD=$SOPS_AGE_KEY_CMD"

# reload:
#   set --export LIBDBG_RELOAD 1
#   source ~/.config/fish/lib/libdbg.fish

if set --query __LIBDBG_LOADED
    if not set --query LIBDBG_RELOAD
        exit 0
    end
end

set --global __LIBDBG_LOADED 1

# true if debug helpers are active
# dbg_* is for developers tracing *this* tool. operators can leave LOG_LEVEL
# at info and set DBG_ENABLED=0 so helpers go quiet without hiding errors.
function dbg_enabled --description 'true if debug helpers are active'
    if set --query DBG_ENABLED
        test "$DBG_ENABLED" != 0
        return $status
    end

    return 0
end

# debug helper output (stderr)
function dbg_print --description 'debug helper output (stderr)'
    dbg_enabled; or return 0
    __liblog_write debug $argv
end

# extra-verbose trace (DBG_TRACE=1)
function dbg_trace --description 'extra-verbose trace (DBG_TRACE=1)'
    if set --query DBG_TRACE; and test "$DBG_TRACE" != 0
        __liblog_write trace $argv
    end
end

# example: dbg_kv pwd (pwd)  →  debug: pwd=/Users/you/proj
# keys whose names look like secrets are redacted, EXCEPT SOPS_AGE_KEY_CMD
# which is a command string (op read op://...), not key material.
function dbg_kv --description 'dbg_kv key value — empty → (unset); secret-ish keys redacted'
    dbg_enabled; or return 0

    if test (count $argv) -lt 2
        return 0
    end

    set --local k $argv[1]
    set --local v $argv[2]

    if test -z "$v"
        set v '(unset)'
    end

    if string match --quiet --ignore-case -- '*key*' $k; or string match --quiet --ignore-case -- '*token*' $k; or string match --quiet --ignore-case -- '*secret*' $k; or string match --quiet --ignore-case -- '*password*' $k
        set v '[REDACTED]'
    end
    __liblog_write debug "$k=$v"
end

# log a command line (already-safe argv)
function dbg_cmd --description 'log a command line (already-safe argv)'
    # caller must pass argv that does not include secret *values*.
    # redact still runs in case a key snuck into a flag.
    dbg_enabled; or return 0
    set --local shown (__liblog_redact (string join -- ' ' $argv))
    __liblog_write debug "exec: $shown"
end

# dbg_check LABEL COMMAND... -- log pass/fail, return command status
function dbg_check --description 'dbg_check LABEL COMMAND... -- log pass/fail, return command status'
    # example:
    #   dbg_check "sops present" __sopsx_check_sops
    #   or return 1
    set --local label $argv[1]
    set --erase argv[1]

    if test (count $argv) -eq 0
        log_error "dbg_check: missing command for '$label'"
        return 2
    end

    dbg_trace "check start: $label"
    $argv

    set --local st $status

    if test $st -eq 0
        dbg_enabled; and __liblog_write debug "check PASS: $label"
        return 0
    end

    __liblog_write error "check FAIL: $label (exit $st)"
    return $st
end

# dbg_assert LABEL COMMAND... — fatal on failure
function dbg_assert --description 'dbg_assert LABEL COMMAND... — fatal on failure'
    dbg_check $argv
    or begin
        log_fatal "assertion failed: $argv[1]"
        return 1
    end
end

# set a named timer
function dbg_timer_start --description 'set a named timer'
    # wall-clock seconds (not high-res). nested names are independent.
    #   dbg_timer_start encrypt
    #   ... work ...
    #   dbg_timer_end encrypt    →  debug: timer encrypt=2s
    set --local name $argv[1]

    if test -z "$name"
        set name default
    end

    set --global __DBG_TIMER_$name (date +%s)
end

# log elapsed seconds for a named timer
function dbg_timer_end --description 'log elapsed seconds for a named timer'
    set --local name $argv[1]

    if test -z "$name"
        set name default
    end

    set --local key __DBG_TIMER_$name

    if not set --query $key
        return 0
    end

    set --local started $$key
    set --local now (date +%s)
    set --local elapsed (math $now - $started)
    dbg_print "timer $name=$elapsed sec"
    set --erase $key
end