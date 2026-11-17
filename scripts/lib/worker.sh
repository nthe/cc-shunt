#!/usr/bin/env bash
# Adapted from Spotify Shunt (Apache-2.0). Changed: local CLI transport.

shunt_error() { printf 'Error: %s\n' "$*" >&2; return 1; }

shunt_cleanup() {
  if [[ -n ${shunt_timer:-} ]]; then kill -KILL -- "-$shunt_timer" 2>/dev/null || :; fi
  if [[ -n ${shunt_worker:-} ]]; then kill -KILL -- "-$shunt_worker" 2>/dev/null || :; fi
  [[ -z ${shunt_stage:-} ]] || rm -f -- "$shunt_stage"
  [[ -z ${shunt_work:-} ]] || rm -rf -- "$shunt_work"
  return 0
}

shunt_settings() {
  local tool
  for tool in jq iconv; do
    command -v "$tool" >/dev/null 2>&1 || { shunt_error "$tool is required"; return 1; }
  done
  [[ -z ${SHUNT_ACTIVE:-} ]] || { shunt_error 'nested Shunt calls are not permitted'; return 1; }
  shunt_limit=${SHUNT_MAX_PAYLOAD_BYTES:-400000}
  shunt_timeout=${SHUNT_TIMEOUT_SECONDS:-180}
  local value
  for value in "$shunt_limit" "$shunt_timeout"; do
    # Bound integer length before Bash arithmetic. Use decimal, including leading zeros.
    if ! [[ $value =~ ^[0-9]{1,9}$ ]] || ((10#$value <= 0)); then
      shunt_error 'size and timeout must be positive integers of at most nine digits'; return 1
    fi
  done
  shunt_limit=$((10#$shunt_limit))
  shunt_timeout=$((10#$shunt_timeout))
}

shunt_init() {
  shunt_settings || return 1
  shunt_work=$(mktemp -d "${TMPDIR:-/tmp}/shunt.XXXXXXXX") || return 1
  # TMPDIR can be relative. Workers need absolute paths after changing directory.
  shunt_work=$(cd "$shunt_work" && pwd -P) || return 1
  shunt_worker='' shunt_timer='' shunt_stage=''
  trap shunt_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
}

# Parse command arguments without eval or command substitution. Preserve quoted paths.
shunt_command() {
  local input=${SHUNT_COMMAND:-} token='' state=plain active=0 char next i
  SHUNT_CMD=()
  for ((i=0; i<${#input}; i++)); do
    char=${input:i:1}
    case $state in
      single) if [[ $char == "'" ]]; then state=plain; else token+=$char; fi ;;
      double)
        if [[ $char == '"' ]]; then state=plain
        elif [[ $char == "\\" ]]; then
          ((i+=1)); ((i<${#input})) || { shunt_error 'incomplete command escape'; return 1; }
          next=${input:i:1}
          case $next in '"'|"\\"|'$'|'`') token+=$next ;; *) token+="\$next" ;; esac
        else token+=$char; fi ;;
      plain)
        case $char in
          "'") state=single; active=1 ;;
          '"') state=double; active=1 ;;
          "\\")
            ((i+=1)); ((i<${#input})) || { shunt_error 'incomplete command escape'; return 1; }
            token+=${input:i:1}; active=1 ;;
          ' '|$'\t'|$'\n')
            if ((active)); then SHUNT_CMD+=("$token"); token=; active=0; fi ;;
          *) token+=$char; active=1 ;;
        esac ;;
    esac
  done
  [[ $state == plain ]] || { shunt_error 'unclosed command quote'; return 1; }
  if ((active)); then SHUNT_CMD+=("$token"); fi
  ((${#SHUNT_CMD[@]})) && [[ -n ${SHUNT_CMD[0]} ]] || {
    shunt_error 'set SHUNT_COMMAND to a command that reads stdin and prints text'; return 1;
  }
}

shunt_invoke() {
  local backend=$1 model=$2 mode=${3:-text} rc=0 worker_cwd=$shunt_work worker_tools=''
  [[ $mode != scout ]] || worker_tools='Read,Grep,Glob'
  case $backend in
    claude)
      SHUNT_CMD=(claude -p --model "${model:-haiku}" --tools "$worker_tools"
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' --setting-sources ''
        --no-session-persistence --output-format json --system-prompt 'Follow the supplied task.') ;;
    codex)
      [[ -n $model ]] || { shunt_error 'set SHUNT_MODEL to a worker model ID available in Codex'; return 1; }
      SHUNT_CMD=(codex exec --model "$model" --sandbox read-only --skip-git-repo-check
        --ephemeral --color never -c features.multi_agent=false -c features.shell_tool=false
        -c 'mcp_servers.shunt_reader={command="false",enabled=false}'
        --output-last-message "$shunt_work/answer" -) ;;
    command) shunt_command || return 1 ;;
    *) shunt_error "unsupported backend: $backend"; return 1 ;;
  esac
  if [[ $mode == scout ]]; then
    worker_cwd=$SHUNT_PROJECT_ROOT
    case $backend in
      claude)
        SHUNT_CMD+=(--max-turns 12) ;;
      codex)
        SHUNT_CMD+=(-c features.shell_tool=true -c features.hooks=false) ;;
    esac
  fi
  command -v "${SHUNT_CMD[0]}" >/dev/null 2>&1 || {
    shunt_error "worker command not found: ${SHUNT_CMD[0]}"; return 1;
  }
  # Job control gives each background job a process group on macOS and Linux.
  set -m
  (
    cd "$worker_cwd" || exit 1
    export SHUNT_ACTIVE=1 SHUNT_TASK_MODE SHUNT_PROJECT_ROOT
    unset CLAUDECODE
    exec "${SHUNT_CMD[@]}"
  ) < "$shunt_work/message" > "$shunt_work/stdout" 2> "$shunt_work/stderr" &
  shunt_worker=$!
  (
    sleep "$shunt_timeout"
    : > "$shunt_work/timed-out"
    kill -KILL -- "-$shunt_worker" 2>/dev/null || :
  ) > /dev/null 2>&1 &
  shunt_timer=$!
  set +m
  wait "$shunt_worker" 2>/dev/null || rc=$?
  # Stop and reap the watchdog, including its sleep child.
  kill -KILL -- "-$shunt_timer" 2>/dev/null || :
  wait "$shunt_timer" 2>/dev/null || :
  shunt_timer=
  # A worker can leave child processes after its own exit.
  kill -KILL -- "-$shunt_worker" 2>/dev/null || :
  shunt_worker=
  if [[ -e $shunt_work/timed-out ]]; then
    shunt_error "worker stopped; time limit is $shunt_timeout seconds"; return 1
  fi
  if ((rc)); then
    shunt_error "worker failed ($rc)"
    tail -c 2000 "$shunt_work/stderr" >&2
    return 1
  fi
  case $backend in
    claude)
      jq -er 'if type == "object" and (.is_error != true) and (.result | type == "string")
              then .result else error("worker returned an error or invalid response") end' \
        "$shunt_work/stdout" > "$shunt_work/answer" || {
          shunt_error 'Claude returned an error or invalid response'; return 1;
        } ;;
    command) cp "$shunt_work/stdout" "$shunt_work/answer" || return 1 ;;
  esac
  if [[ ! -f $shunt_work/answer ]] || ! LC_ALL=C grep -q '[^[:space:]]' "$shunt_work/answer"; then
    shunt_error 'worker returned no text'; return 1
  fi
}
