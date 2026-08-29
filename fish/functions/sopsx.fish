#!/usr/bin/env fish

# ~/.config/fish/functions/sopsx.fish
# small wrapper for `sops, and age` with `op`

# validate: fish --no-execute sopsx.fish
# format: fish_indent --write sopsx.fish

# ?
# small, wrapper around `sops` for age encryption, where the
# age *private* key lives in 1Password and is fetched by `sops` itself via:
#   set --global --export SOPS_AGE_KEY_CMD 'op read op://vault/age-sops/private-key'

# this script NEVER:
#   - eval's SOPS_AGE_KEY_CMD
#   - stores private key in a fish_variable
#   - prints file contents (plaintext/ciphertext) to the logger or output

# sops runs SOPS_AGE_KEY_CMD as a subprocess and reads the key from that
# command's stdout. the shell only sees the command *string*, not the key.

# typical setup:
# 1. store an age identity in 1Password (item field = the AGE-SECRET-KEY-1... line).
#
# 2. in config.fish (or a secrets env file that is not committed):
#      set --global --export SOPS_AGE_KEY_CMD 'op read op://personal/age-sops/private-key'
#      # optional if you do not use .sops.yaml:
#      set --global --export SOPS_AGE_RECIPIENTS 'age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
#
# 3. sign in to op cli once per session:
#      op signin
#
# 4. optional project rules (walks up from cwd):
#      # .sops.yaml
#      creation_rules:
#        - path_regex: \.env$
#          age: age1xxxxxxxx...

# examples:
# 1. first-time health check
#   sopsx doctor
#   # fails if sops missing, SOPS_AGE_KEY_CMD unset, `op` not signed in, etc.
#
# 2. encrypt a dotenv, write ciphertext to stdout (pipe / capture)
#   sopsx encrypt .env > .env.enc
#   # logs on stderr; ciphertext only on stdout.
#
# 3. encrypt in place (file becomes sops YAML/JSON/dotenv ciphertext)
#   sopsx encrypt secrets.yaml -i
#
# 4. encrypt to a new path, refuse overwrite unless --force
#   sopsx encrypt app.env -o app.env.sops
#   sopsx encrypt app.env -o app.env.sops --force
#
# 5. explicit recipient (overrides / supplements env + .sops.yaml)
#   sopsx encrypt secrets.yaml --age age1qxy... -o secrets.enc.yaml
#
# 6. decrypt to stdout (common: feed another tool)
#   sopsx decrypt secrets.enc.yaml | kubectl apply -f -
#
# 7. decrypt in place (file becomes plaintext -- treat as secret!)
#   sopsx decrypt secrets.enc.yaml -i
#
# 8. decrypt to a file that already exists
#   sopsx decrypt secrets.enc.yaml -o /tmp/plain.yaml          # error if exists
#   sopsx decrypt secrets.enc.yaml -o /tmp/plain.yaml --force  # overwrite
#
# 9. dry-run (preflight + planned argv, no sops write)
#   sopsx encrypt .env -o .env.sops --dry-run
#   sopsx decrypt .env.sops --dry-run
#
# 10. already-encrypted input / plaintext decrypt
#   sopsx encrypt already.enc.yaml        # refused
#   sopsx encrypt already.enc.yaml --force
#   sopsx decrypt plaintext.yaml          # refused
#   sopsx decrypt plaintext.yaml --force  # still runs sops (usually fails)
#
# 11. quiet CI (errors/fatal only)
#   sopsx encrypt .env -o .env.sops -q
#   # or: set --export LOG_QUIET 1
#
# 12. skip preflight (you already ran doctor; faster inner loop)
#   set --export SOPSX_SKIP_DOCTOR 1
#   sopsx encrypt .env -i
#
# 13. debug less / more
#   set --export LOG_LEVEL info          # hide debug
#   set --export DBG_ENABLED 0           # silence dbg_* helpers
#   set --export DBG_TRACE 1             # extra check tracing
#   set --export LOG_COLOR never         # no ANSI (logs / CI)
#
# 14. aliases accepted by the dispatcher
#   sopsx e / sopsx enc / sopsx encrypt
#   sopsx d / sopsx dec / sopsx decrypt
#   sopsx check / sopsx preflight / sopsx doctor
#
# 15. reload after editing this file in an already-open shell
#   set --export SOPSX_RELOAD 1
#   source ~/.config/fish/functions/sopsx.fish
#   set --erase SOPSX_RELOAD

# security constraints
#   - all logs go to stderr (stdout is for ciphertext/plaintext only)
#   - private keys are never assigned to Fish variables
#   - SOPS_AGE_KEY_CMD is never eval'd here; sops executes it
#   - command lines are redacted before logging
#   - file contents are never logged
#   - atomic writes + umask 077 for any temp files
#   - existing outputs require --force unless --in-place

# env:
#   SOPS_AGE_KEY_CMD     command sops runs to fetch the age private key
#   SOPS_AGE_RECIPIENTS  optional comma-separated age public keys
#   LOG_LEVEL            trace|debug|info|warn|error|fatal  (default: debug)
#   LOG_PREFIX           logger name (default: sopsx)
#   LOG_COLOR            auto|always|never                  (default: auto)
#   LOG_QUIET            1 = errors/fatal only
#   DBG_ENABLED          1/0  (default: 1 — debug helpers on)
#   DBG_TRACE            1    extra command tracing
#   SOPSX_SKIP_DOCTOR  1    skip preflight on encrypt/decrypt

# exit codes (conventional):
#   0  success
#   1  runtime / preflight / sops failure
#   2  usage / bad arguments / missing file

# guard (idempotent source)
# fish autoloads this file when `sopsx` is first invoked.
# if you `source` it again in the same session, skip redefinition unless SOPSX_RELOAD is set.
# `exit 0` here exits the *source file*, not the interactive shell.
if set --query __sopsx_file_loaded
    # allow re-source in the same session only if caller asks
    if not set --query SOPSX_RELOAD
        exit 0
    end
end

set --global __SOPSX_FILE_LOADED 1
set --global SOPSX_VERSION 1.0.0

# load fish lib
set --local __dbg_libdir "$HOME/.config/fish/lib"

if set --query DBG_LIBDIR; and test -n "$DBG_LIBDIR"
    set __dbg_libdir $DBG_LIBDIR
end

if not test -f "$__dbg_libdir/liblog.fish"
    echo "sopsx: missing $__dbg_libdir/liblog.fish" >&2
    exit 1
end

if not test -f "$__dbg_libdir/libdbg.fish"
    echo "sopsx: missing $__dbg_libdir/libdbg.fish" >&2
    exit 1
end

if not test -f "$__dbg_libdir/libsopsx.fish"
    echo "sopsx: missing $__dbg_libdir/libsopsx.fish" >&2
    exit 1
end

source "$__dbg_libdir/liblog.fish"
source "$__dbg_libdir/libdbg.fish"
source "$__dbg_libdir/libsopsx.fish"

# one-liner for sourcing in current-session
# set --export SOPSX_RELOAD 1 LIBLOG_RELOAD 1 LIBDBG_RELOAD 1 LIBSOPSX_RELOAD 1; source ~/.config/fish/functions/sopsx.fish; set --erase SOPSX_RELOAD LIBLOG_RELOAD LIBDBG_RELOAD LIBSOPSX_RELOAD; functions --query sopsx; and echo sopsx ok; functions --query log_info; and echo liblog ok; functions --query dbg_kv; and echo libdbg ok; functions --query dbg_file_info; and echo libsopsx ok; sopsx version

# print TMPDIR if set, otherwise /tmp
function __sopsx_tmpdir --description 'print TMPDIR if set, otherwise /tmp'
    # prefer TMPDIR (macOS often /var/folders/...); else /tmp.
    if set --query TMPDIR; and test -n "$TMPDIR"
        echo $TMPDIR
        return
    end

    echo /tmp
end

# full path of a binary, or fail. `command --search` does not run it.
function __sopsx_which --description 'print full path of a command without executing it'
    command --search $argv[1]
end

# return 0 if a command name exists in PATH
function __sopsx_have_cmd --description 'return 0 if a command name exists in PATH'
    command --query $argv[1]
end

# parse the first token of SOPS_AGE_KEY_CMD without executing it
# parse only - never eval. example:
#   'op read op://vault/item/field'  →  op
#   "'/usr/local/bin/op' read ..."   →  /usr/local/bin/op  (quotes stripped)
function __sopsx_key_cmd_bin --description 'first token of SOPS_AGE_KEY_CMD (not executed)'
    if not set --query SOPS_AGE_KEY_CMD; or test -z "$SOPS_AGE_KEY_CMD"
        return 1
    end

    set --local raw (string trim -- $SOPS_AGE_KEY_CMD)
    set --local tok (string split --fields 1 -- ' ' $raw)
    set tok (string trim --chars '\'"' -- $tok)

    echo $tok
end

# return 0 if SOPS_AGE_KEY_CMD appears to invoke the op-cli
function __sopsx_key_cmd_looks_like_op --description 'return 0 if SOPS_AGE_KEY_CMD appears to invoke the op-cli'
    # matches "op ..." or a binary whose first token is exactly `op`.
    if not set --query SOPS_AGE_KEY_CMD
        return 1
    end

    string match --regex --quiet -- '(^|[[:space:]])op[[:space:]]' $SOPS_AGE_KEY_CMD
    or string match --quiet -- 'op' (__sopsx_key_cmd_bin)
end

# walk from cwd to filesystem root looking for .sops.yaml or .sops.yml.
# example: cwd=/a/b/c → /a/b/c/.sops.yaml, /a/b/.sops.yaml, /a/.sops.yaml, /.sops.yaml
function __sopsx_find_sops_yaml --description 'walk from cwd to root and print the first .sops.yaml or .sops.yml'
    set --local dir (pwd)

    while true
        if test -f $dir/.sops.yaml
            echo $dir/.sops.yaml
            return 0
        end

        if test -f $dir/.sops.yml
            echo $dir/.sops.yml
            return 0
        end

        set --local parent (dirname -- $dir)

        if test "$parent" = "$dir"
            break
        end

        set dir $parent
    end

    return 1
end

# best-effort sops encryption detection
function __sopsx_is_encrypted --description 'best-effort check whether a file is sops-encrypted'
    # prefer `sops filestatus` JSON: {"encrypted":true}
    # fallback: a top-level `sops:` key (yaml metadata). never prints the file.
    set --local p $argv[1]

    if not test -f $p
        return 1
    end

    if command sops filestatus -- $p >/dev/null 2>&1
        set --local st (command sops filestatus -- $p 2>/dev/null)

        if string match --quiet -- '*"encrypted":true*' $st; or string match --quiet -- '*"encrypted": true*' $st
            return 0
        end

        return 1
    end

    # fallback: sops metadata block (do not print file)
    command grep --quiet -- '^sops:' $p 2>/dev/null
    return $status
end

# shared input validation for encrypt/decrypt.
# empty, directory, missing, non-regular, unreadable → error 2.
# paths with `..` are warned but allowed if the resolved file exists
# (avoids surprising users with relative paths like ../secrets/prod.env).
function __sopsx_require_file --description 'validate that PATH is a readable regular file; return 2 on failure'
    set --local p $argv[1]

    if test -z "$p"
        log_error "path is empty"
        return 2
    end

    if string match --quiet -- '*..*' $p
        log_warn "path contains '..' -- resolving and continuing only if the file exists"
    end

    if test -d $p
        log_error "path is a directory: $p"
        return 2
    end

    if not test -e $p
        log_error "file does not exist: $p"
        return 2
    end

    if not test -f $p
        log_error "not a regular file: $p"
        return 2
    end

    if not test -r $p
        log_error "file is not readable: $p"
        return 2
    end

    return 0
end

# for -o FILE: do not clobber unless force=1
# directory must exist and be writable.
# --in-place is handled by sops itself, so this is not used for -i.
function __sopsx_protect_output --description 'refuse to overwrite output-file unless force=1; require a writable parent directory'
    set --local out $argv[1]
    set --local force $argv[2]

    if test -z "$out"
        return 0
    end

    if test -e $out
        if test "$force" != 1
            log_error "refusing to overwrite existing file (pass --force): $out"
            return 1
        end

        log_warn "overwriting existing file: $out"
    end

    set --local dir (dirname -- $out)

    if not test -d $dir
        log_error "output directory does not exist: $dir"
        return 1
    end

    if not test -w $dir
        log_error "output directory is not writable: $dir"
        return 1
    end

    return 0
end

# umask 077 so the temp file is 600 even if mktemp's template is world-readable
# on a given OS. Pattern: $TMPDIR/sopsx.<uid>.XXXXXX
function __sopsx_mktemp --description 'create a 0600 temp file under tmpdir named sopsx.<uid>.XXXXXX'
    set --local old_umask (umask)
    umask 077
    set --local t (mktemp (printf '%s/sopsx.%s.XXXXXX' (__sopsx_tmpdir) (id -u)))
    set --local st $status

    umask $old_umask

    if test $st -ne 0; or test -z "$t"
        log_error "mktemp failed"
        return 1
    end

    echo $t
end

# logs the argv (redacted) then execs sops with the same stdout as the caller.
# that is how `sopsx decrypt f.yaml > plain.yaml` works.
function __sopsx_run_sops --description 'run sops with the given argv; log the command, never log stdout'
    dbg_cmd command sops $argv
    command sops $argv
    return $status
end

# require sops in PATH and log its version
function __sopsx_check_sops --description 'require sops in PATH and log its version'
    if not __sopsx_have_cmd sops
        log_error "sops not found in PATH"
        return 1
    end

    set --local ver (command sops --version --check-for-updates 2>/dev/null | string collect)
    dbg_kv sops_version (string replace --regex --all '\n' ' ' -- $ver)
    return 0
end

# sops embeds age; the standalone `age` cli is only useful for keygen/debug.
function __sopsx_check_age_optional --description 'log age cli version if present; warn if missing (sops embeds age)'
    if __sopsx_have_cmd age
        set --local ver (command age --version 2>/dev/null)
        dbg_kv age_version $ver
        return 0
    end

    log_warn "age cli not in PATH (optional; sops has built-in age)"
    return 0
end

# need=required  → decrypt/doctor
# need=optional  → encrypt (public-key encrypt does not need the private key,
# but in-place recrypt / later decrypt will)
function __sopsx_check_key_cmd --argument-names need --description 'validate SOPS_AGE_KEY_CMD (need=required|optional) without executing it'
    if not set --query SOPS_AGE_KEY_CMD; or test -z "$SOPS_AGE_KEY_CMD"
        if test "$need" = required
            log_error "SOPS_AGE_KEY_CMD is not set"
            log_error "example: set --global --export SOPS_AGE_KEY_CMD 'op read op://vault/age-sops/private-key'"
            return 1
        end

        log_warn "SOPS_AGE_KEY_CMD is not set (needed for decrypt / in-place recrypt)"
        return 0
    end

    dbg_kv SOPS_AGE_KEY_CMD $SOPS_AGE_KEY_CMD

    # sops typically runs KEY_CMD through a shell. metacharacters ($ ` $( )) are
    # a footgun; keep the value a simple `op read op://...` string.
    if string match --regex --quiet -- '[$`]|\$\(' $SOPS_AGE_KEY_CMD
        log_warn "SOPS_AGE_KEY_CMD contains shell metacharacters; sops will run it via a shell -- keep it a simple 'op read op://...' form"
    end

    set --local bin (__sopsx_key_cmd_bin)

    or begin
        log_error "unable to parse SOPS_AGE_KEY_CMD"
        return 1
    end

    if not __sopsx_have_cmd $bin
        log_error "SOPS_AGE_KEY_CMD binary not in PATH: $bin"
        return 1
    end

    dbg_kv key_cmd_bin (__sopsx_which $bin)
    return 0
end

# skip if KEY_CMD is not 1Password (e.g. a custom helper script).
function __sopsx_check_op_session --description 'if KEY_CMD looks like op, require op cli and an authenticated session'
    __sopsx_key_cmd_looks_like_op; or return 0

    if not __sopsx_have_cmd op
        log_error "op cli 'op' not found in PATH"
        return 1
    end

    set --local ver (command op --version 2>/dev/null)
    dbg_kv op_version $ver

    # command op whoami >/dev/null 2>&1
    # set --local st $status
    set --local state (op account get --format=json | jq -r '.state')

    # if test $st -ne 0
    if test "$state" != "ACTIVE"
        log_error "op cli is not authenticated (op whoami failed)"
        log_error "run: op signin"
        return 1
    end

    dbg_print "1Password session: ok"

    return 0
end

# recipient resolution order:
#   1. .sops.yaml / .sops.yml walking up from cwd
#   2. --age age1... on the CLI
#   3. SOPS_AGE_RECIPIENTS
# encrypt fails if none of these exist (sops would fail later anyway).
function __sopsx_check_recipients --argument-names age_cli --description 'ensure an age recipient exists via .sops.yaml, --age, or SOPS_AGE_RECIPIENTS'
    set --local cfg (__sopsx_find_sops_yaml)

    if test $status -eq 0
        dbg_kv sops_yaml $cfg
        return 0
    end

    if test -n "$age_cli"
        dbg_kv age_recipient $age_cli

        if not string match --regex --quiet -- '^age1[0-9a-z]+$' $age_cli
            log_warn "age public key does not match age1... pattern: $age_cli"
        end

        return 0
    end

    if set --query SOPS_AGE_RECIPIENTS; and test -n "$SOPS_AGE_RECIPIENTS"
        dbg_kv SOPS_AGE_RECIPIENTS $SOPS_AGE_RECIPIENTS
        return 0
    end

    log_error "no age recipient: pass --age, set SOPS_AGE_RECIPIENTS, or add .sops.yaml"
    return 1
end

# mode: encrypt | decrypt | doctor
function __sopsx_preflight --argument-names mode age_cli --description 'run encrypt/decrypt/doctor dependency checks before calling sops'
    log_debug "preflight start mode=$mode"
    dbg_check "sops present" __sopsx_check_sops

    or return 1
    __sopsx_check_age_optional

    switch $mode
        case encrypt
            __sopsx_check_key_cmd optional
            or return 1
            __sopsx_check_op_session
            or return 1
            __sopsx_check_recipients $age_cli
            or return 1

        case decrypt doctor
            __sopsx_check_key_cmd required
            or return 1
            __sopsx_check_op_session
            or return 1

            if test $mode = doctor
                __sopsx_check_recipients $age_cli
                # recipient missing is a warning for doctor
                true
            end

        case '*'
            log_error "internal: unknown preflight mode $mode"
            return 2
    end

    if set --query SOPS_AGE_KEY
        log_warn "SOPS_AGE_KEY is exported -- child processes can inherit private key material"
    end

    log_debug "preflight ok"
    return 0
end

# run sopsx preflight checks and report .sops.yaml discovery"
function __sopsx_doctor --description 'run sopsx preflight checks and report .sops.yaml discovery'
    argparse --names 'sopsx doctor' 'h/help' -- $argv
    or return 2

    if set --query _flag_help
        printf '%s\n' 'usage: sopsx doctor' >&2
        return 0
    end

    set --global LOG_PREFIX sopsx
    log_info "sopsx doctor v$SOPSX_VERSION"
    dbg_banner

    set --local failed 0
    __sopsx_preflight doctor ''
    or set failed 1

    set --local cfg (__sopsx_find_sops_yaml)
    if test $status -eq 0
        log_info "found creation rules: $cfg"
        dbg_file_info $cfg
    else
        log_warn "no .sops.yaml/.sops.yml found from $(pwd) upward"
    end

    if test $failed -eq 0
        log_success "doctor: all required checks passed"
        return 0
    end

    log_error "doctor: one or more required checks failed"
    return 1
end

# print sopsx usage and notes to stderr
function __sopsx_usage --description 'print sopsx usage and notes to stderr'
        echo "sopsx v$SOPSX_VERSION -- sops + age + op"
        echo
        echo "usage:"
        echo "  sopsx encrypt  FILE [-i] [-o OUT] [--age age1...] [--force] [--dry-run]"
        echo "  sopsx decrypt  FILE [-i] [-o OUT] [--force] [--dry-run]"
        echo
        echo "options:"
        echo "  -i, --in-place     rewrite FILE"
        echo "  -o, --output OUT   write to OUT (exclusive with -i)"
        echo "      --age KEY      recipient public key (encrypt)"
        echo "      --force        overwrite / override safety checks"
        echo "      --dry-run      preflight + plan only"
        echo "  -q, --quiet        errors only"
        echo "  -h, --help         show help"
        echo
        echo "examples:"
        echo "  sopsx encrypt secrets.yaml -o secrets.enc.yaml"
        echo "  sopsx decrypt secrets.enc.yaml > secrets.yaml"
        echo "  sopsx decrypt secrets.enc.yaml -o /tmp/plain.yaml --force"
        echo "  sopsx encrypt .env -o .env.sops --dry-run >&2"
end

# flow:
#   parse flags → require FILE → optional preflight → refuse double-encrypt
#   → build sops --encrypt argv → dry-run or run → verify in-place result
function __sopsx_encrypt --description 'encrypt FILE with sops --encrypt (age / .sops.yaml / SOPS_AGE_RECIPIENTS)'
    argparse --name 'sopsx encrypt' 'h/help' 'i/in-place' 'o/output=' 'age=' 'force' 'dry-run' 'q/quiet' -- $argv
    or return 2

    if set --query _flag_help
        __sopsx_usage
        return 0
    end

    if set --query _flag_quiet
        set --global LOG_QUIET 1
    end

    set --local file $argv[1]
    if test -z "$file"
        log_error "encrypt: FILE is required"
        __sopsx_usage
        return 2
    end

    if test (count $argv) -gt 1
        log_error "encrypt: extra arguments: $argv[2..-1]"
        return 2
    end

    if set --query _flag_in_place; and set --query _flag_output
        log_error "encrypt: --in-place and --output are mutually exclusive"
        return 2
    end

    dbg_banner
    dbg_file_info $file
    __sopsx_require_file $file
    or return 2

    set --local age_cli ''
    if set --query _flag_age
        set age_cli $_flag_age
    end

    if not set --query SOPSX_SKIP_DOCTOR; or test "$SOPSX_SKIP_DOCTOR" = 0
        __sopsx_preflight encrypt $age_cli
        or return 1
    end

    if __sopsx_is_encrypted $file
        log_warn "input already looks sops-encrypted: $file"

        if not set --query _flag_force
            log_error "refusing to encrypt an encrypted file (pass --force to override)"
            return 1
        end
    end

    set --local sops_args --encrypt

    if test -n "$age_cli"
        set --append sops_args --age $age_cli
    end

    if set --query _flag_in_place
        set --append sops_args --in-place
    else if set --query _flag_output
        set --local force 0
        set --query _flag_force; and set force 1

        __sopsx_protect_output $_flag_output $force
        or return 1

        set --append sops_args --output $_flag_output
    end

    log_info "encrypt plan input=$file in_place=$(set --query _flag_in_place; and echo 1; or echo 0) output=$(set --query _flag_output; and echo $_flag_output; or echo '-')"

    if set --query _flag_dry_run
        log_info "dry-run: skipping sops"
        dbg_cmd sops $sops_args -- $file
        return 0
    end

    dbg_timer_start encrypt
    __sopsx_run_sops $sops_args -- $file
    set --local st $status
    dbg_timer_end encrypt

    if test $st -ne 0
        log_error "sops encrypt failed (exit $st)"
        return $st
    end

    if set --query _flag_in_place
        dbg_file_info $file
        if not __sopsx_is_encrypted $file
            log_warn "in-place encrypt finished but file does not look encrypted"
        end
    else if set --query _flag_output
        dbg_file_info $_flag_output
    end

    log_success "encrypt ok"
    return 0
end

# flow mirrors encrypt. without -i/-o, plaintext is written to stdout.
# decrypt requires SOPS_AGE_KEY_CMD so sops can fetch the age identity.
function __sopsx_decrypt --description 'decrypt FILE with sops --decrypt using SOPS_AGE_KEY_CMD'
    argparse --name 'sopsx decrypt' 'h/help' 'i/in-place' 'o/output=' 'force' 'dry-run' 'q/quiet' -- $argv
    or return 2

    if set --query _flag_help
        __sopsx_usage
        return 0
    end

    if set --query _flag_quiet
        set --global LOG_QUIET 1
    end

    set --local file $argv[1]

    if test -z "$file"
        log_error "decrypt: FILE is required"
        __sopsx_usage
        return 2
    end

    if test (count $argv) -gt 1
        log_error "decrypt: extra arguments: $argv[2..-1]"
        return 2
    end

    if set --query _flag_in_place; and set --query _flag_output
        log_error "decrypt: --in-place and --output are mutually exclusive"
        return 2
    end

    dbg_banner
    dbg_file_info $file

    __sopsx_require_file $file
    or return 2

    if not set --query SOPSX_SKIP_DOCTOR; or test "$SOPSX_SKIP_DOCTOR" = 0
        __sopsx_preflight decrypt ''
        or return 1
    end

    if not __sopsx_is_encrypted $file
        log_warn "input does not look sops-encrypted: $file"
        if not set --query _flag_force
            log_error "refusing to decrypt plaintext (pass --force to override)"
            return 1
        end
    end

    set --local sops_args --decrypt

    if set --query _flag_in_place
        set --append sops_args --in-place
    else if set --query _flag_output
        set --local force 0
        set --query _flag_force; and set force 1

        __sopsx_protect_output $_flag_output $force
        or return 1

        set --append sops_args --output $_flag_output
    else
        log_debug "decrypt writing plaintext to stdout"
    end

    log_info "decrypt plan input=$file in_place=$(set --query _flag_in_place; and echo 1; or echo 0) output=$(set --query _flag_output; and echo $_flag_output; or echo '-')"

    if set --query _flag_dry_run
        log_info "dry-run: skipping sops"
        dbg_cmd sops $sops_args -- $file
        return 0
    end

    dbg_timer_start decrypt
    __sopsx_run_sops $sops_args -- $file
    set --local st $status
    dbg_timer_end decrypt

    if test $st -ne 0
        log_error "sops decrypt failed (exit $st) -- check op session and SOPS_AGE_KEY_CMD"
        return $st
    end

    if set --query _flag_in_place
        dbg_file_info $file
    else if set --query _flag_output
        dbg_file_info $_flag_output
    end

    log_success "decrypt ok"
    return 0
end

# main lazy-loaded function
function sopsx --description 'sops+age encrypt/decrypt using op'
    set --global LOG_PREFIX sopsx

    if test (count $argv) -eq 0
        __sopsx_usage
        return 2
    end

    set --local cmd $argv[1]
    set --erase argv[1]

    switch $cmd
        case encrypt enc e
            __sopsx_encrypt $argv
            return $status

        case decrypt dec d
            __sopsx_decrypt $argv
            return $status

        case doctor check preflight
            __sopsx_doctor $argv
            return $status

        case help -h --help
            __sopsx_usage
            return 0

        case version --version
            printf '%s\n' $SOPSX_VERSION
            return 0

        case '*'
            log_error "unknown command: $cmd"
            __sopsx_usage
            return 2
    end
end

# completions (applied when this file is loaded)
# `complete --command sopsx --no-files` disables filename completion by default; `-o`/`--age`
# re-enable arguments where needed (`-r` = require token, `-x` = exclusive arg).
complete --command sopsx --no-files
complete --command sopsx --condition '__fish_use_subcommand' --arguments encrypt --description 'encrypt a file with sops+age+op'
complete --command sopsx --condition '__fish_use_subcommand' --arguments decrypt --description 'decrypt a sops file'
complete --command sopsx --condition '__fish_use_subcommand' --arguments doctor --description 'run preflight checks'
complete --command sopsx --condition '__fish_use_subcommand' --arguments help --description 'show help'
complete --command sopsx --short-option i --long-option in-place --description 'rewrite the input file'
complete --command sopsx --short-option o --long-option output --require-parameter --description 'write to file'
complete --command sopsx --long-option age --exclusive --description 'age public key (age1...)'
complete --command sopsx --long-option force --description 'overwrite / override safety checks'
complete --command sopsx --long-option dry-run --description 'plan only'
complete --command sopsx --short-option q --long-option quiet --description 'errors only'
complete --command sopsx --short-option h --long-option help --description 'show help'