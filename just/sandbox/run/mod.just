# just/sandbox/run/mod.just — put work into a mounted box, or look inside it.
#
# Two ways in, and they are not interchangeable:
#
#   just sbx run cmd    generic escape hatch, SYNCHRONOUS, prints stdout. Your
#                       inspection tool — a log, a git state, a table.
#   just sbx run agent  hand off to Claude Code inside the box over a RESUMABLE
#                       session, then keep talking to it. For steering.
#
# The third way in is `just sbx lifecycle execute` — the detached full SDLC, and
# the default for real work. It lives with the phases because it writes `pid` to
# the run record; these two write nothing and are not phases.
#
# Nothing here ever destroys a VM. A failure reports and exits non-zero with the
# box left alive, because the evidence you need to diagnose it is on that box.
#
# OPENROUTER_PROVISIONING_KEY is never read in this file and must never be. Only
# the mint/revoke phases touch it, and it never leaves the host. We also never
# ask ssh to forward host env (no SendEnv), so nothing from .env leaks over.
set working-directory := '../../..'
set positional-arguments
set dotenv-load

# list the ways into a sandbox
default:
    @just --list sbx::run

# usage: just sbx run cmd <run-id> uname -a   |   just sbx run cmd <run-id> "tail -20 run.log"
# generic escape hatch: run any command inside a sandbox, synchronously
cmd RUN_ID +CMD:
    #!/usr/bin/env bash
    set -euo pipefail
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    # The run record is the only cross-phase state; `get` fails loudly if the run
    # does not exist, which is the check we want before touching the network.
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "run cmd {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }
    echo "→ run cmd {{RUN_ID}} on $VM: {{CMD}}"
    # {{CMD}} is interpolated verbatim rather than rebuilt from "$@" on purpose:
    # this is an escape hatch, so the pipes, globs and quotes you typed are meant
    # to reach the remote shell intact. `cd app` matches where FILL clones.
    ssh "$VM".exe.xyz "cd app && {{CMD}}"

# usage: just sbx run agent <run-id> "remember the number 42, reply STORED"
#        just sbx run agent <run-id> "what number did I ask you to remember?"
# hand off to Claude Code inside the sandbox, then keep talking to it
agent RUN_ID PROMPT:
    #!/usr/bin/env bash
    set -euo pipefail
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "run agent {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }
    SID=$("$RR" get {{RUN_ID}} session_id)
    [ -n "$SID" ] || { echo "run agent {{RUN_ID}}: no session_id in the run record — CREATE writes it" >&2; exit 1; }

    # First call must be --session-id, every later one --resume, so we need one
    # bit of "has this session started". Chosen: a host sentinel file beside the
    # run record. WHY not the alternatives:
    #   - the run record schema is closed (run_id vm_name https_url key_hash
    #     limit spend session_id commit_sha ports pid created_at closed_at) and
    #     rejects unknown keys, so there is nowhere to put a boolean;
    #   - probing the VM for the session costs an extra ssh round trip on every
    #     turn and depends on Claude Code's on-disk session layout, which we have
    #     NOT verified — an implementation detail is a bad source of truth.
    # The sentinel path is derived from the record's own path so it inherits
    # .sandbox/runs/ (gitignored) rather than hardcoding it here.
    REC=$("$RR" path {{RUN_ID}})
    STARTED="${REC%.json}.agent-started"

    if [ -e "$STARTED" ]; then
        FLAG="--resume $SID"
        echo "→ run agent {{RUN_ID}} on $VM: resuming session $SID"
    else
        FLAG="--session-id $SID"
        echo "→ run agent {{RUN_ID}} on $VM: starting session $SID"
    fi

    PROMPT={{ quote(PROMPT) }}
    Q=$(printf '%q' "$PROMPT")

    # Verbatim from the verified invocation. The base URL is exe.dev's key-free
    # gateway, NOT OpenRouter — OpenRouter does not serve the Anthropic Messages
    # API cleanly, and this lane needs no key at all (ANTHROPIC_API_KEY is a
    # placeholder the client insists on). Synchronous by design: the whole point
    # is to read the reply and send the next turn.
    ssh "$VM".exe.xyz "cd app && ANTHROPIC_API_KEY=implicit ANTHROPIC_BASE_URL=https://llm.int.exe.xyz claude -p $FLAG --dangerously-skip-permissions $Q"

    # Only after a successful turn: a first call that died never created a
    # session, and --resume on a session that does not exist would fail forever.
    touch "$STARTED"

# usage: just sbx run watch <run-id> [stale_seconds]
# staleness watchdog for a detached SDLC: polls the factory's events.jsonl every
# 30s and, once a factory session exists, warns (stderr) when the file has not
# grown for more than STALE seconds (default 300 = 5 min). Alert-only: it never
# aborts the run and exits 0 after warning, so a human or another agent can
# intervene. Ctrl-C stops a long-running watch. The execute recipe's banner probe
# covers the first minute; this covers the rest of the run.
watch RUN_ID *ARGS:
    #!/usr/bin/env bash
    set -u
    RR="{{justfile_directory()}}/sandbox_mount/host/run_record.py"
    VM=$("$RR" get {{RUN_ID}} vm_name)
    [ -n "$VM" ] || { echo "run watch {{RUN_ID}}: no vm_name in the run record — is it mounted?" >&2; exit 1; }
    STALE="${1:-300}"
    POLL=30
    seen=0
    quiet=0
    echo "→ run watch {{RUN_ID}} on $VM — warns if events.jsonl goes quiet > ${STALE}s (alert only; Ctrl-C to stop)"
    while true; do
        out=$(ssh "$VM".exe.xyz 'cd app && f=$(ls -t adws/adw_data/sessions/*/events.jsonl 2>/dev/null | head -1); if [ -n "$f" ]; then stat -c %s\ %Y "$f"; else echo NO_SESSION_YET; fi' 2>/dev/null)
        if [[ "$out" == NO_SESSION_YET ]]; then
            quiet=$((quiet + POLL))
            [ "$seen" = 1 ] && echo "[$(date +%H:%M:%S)] watch: no factory session writes for ${quiet}s — run {{RUN_ID}} may be quiet or stuck" >&2
        else
            read -r size mtime <<< "$out"
            [ -n "${mtime:-}" ] || { echo "watch: could not read events.jsonl on $VM" >&2; exit 1; }
            now=$(date +%s)
            age=$((now - mtime))
            if [ "$age" -gt "$STALE" ]; then
                echo "[$(date +%H:%M:%S)] WARN: events.jsonl (${size}B) not written for ${age}s (stale > ${STALE}s) — run {{RUN_ID}} may be wedged." >&2
                echo "[WARN] check: just sbx run cmd {{RUN_ID}} 'tail -5 run.log'  ·  restart the run with just sbx lifecycle execute {{RUN_ID}} \"<prompt>\"" >&2
                exit 0
            fi
        fi
        seen=1
        sleep "$POLL"
    done
