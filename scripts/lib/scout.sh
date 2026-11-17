#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# shellcheck source=worker.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/worker.sh"

shunt_scout() {
  local project=$PWD request='' backend=${SHUNT_BACKEND:-claude} model=${SHUNT_MODEL:-} path dir file size
  local paths=() starting_paths=()
  while (($#)); do
    case $1 in
      --root|--task|--backend|--model)
        (($# >= 2)) && [[ $2 != --* && ( -n $2 || $1 == --model ) ]] || { shunt_error "missing value for $1"; return 1; }
        case $1 in --root) project=$2 ;; --task) request=$2 ;; --backend) backend=$2 ;; --model) model=$2 ;; esac
        shift 2 ;;
      --paths)
        shift
        while (($#)) && [[ $1 != --* ]]; do paths+=("$1"); shift; done ;;
      --help|-h) echo 'scout --task TEXT --paths PATH... [--root PROJECT] [--backend claude|codex|command] [--model ID]'; return ;;
      *) shunt_error "unknown argument: $1"; return 1 ;;
    esac
  done
  [[ $request =~ [^[:space:]] && ${#paths[@]} -gt 0 && ${#paths[@]} -le 256 ]] || {
    shunt_error 'a task and 1 to 256 starting paths are required'; return 1;
  }
  project=$(cd -P -- "$project" && printf '%s.' "$PWD") || return 1
  project=${project%.}
  [[ $project != / ]] || { shunt_error 'use a project folder'; return 1; }
  for path in "${paths[@]}"; do
    [[ $path == /* ]] || path=$project/$path
    # Resolve directories and file symlinks before checking project scope.
    if [[ -d $path ]]; then
      file=$(cd -P -- "$path" && printf '%s.' "$PWD") || return 1
      file=${file%.}
    else
      # Follow file links with the same physical scope check used for folders.
      local link count=0
      while [[ -L $path ]]; do
        ((count+=1)); ((count <= 40)) || { shunt_error 'too many path links'; return 1; }
        link=$(readlink -n -- "$path" && printf '.') || return 1
        link=${link%.}
        if [[ $link == /* ]]; then path=$link; else path=${path%/*}/$link; fi
      done
      dir=$(cd -P -- "${path%/*}" && printf '%s.' "$PWD") || return 1
      file=${dir%.}/${path##*/}
      [[ -f $file && -r $file ]] || { shunt_error 'starting paths must be readable files or folders'; return 1; }
    fi
    [[ $file == "$project" || $file == "$project/"* ]] || { shunt_error 'starting paths must be inside the project'; return 1; }
    starting_paths+=("$file")
  done
  shunt_init || return 1
  cat "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && cd ../.. && pwd)/prompts/scout.md" > "$shunt_work/message" || return 1
  printf '\nProject: %s\nRequest: ' "$project" >> "$shunt_work/message"
  printf '%s\0' "${starting_paths[@]}" | jq -Rsc --arg task "$request" '{paths:(split("\u0000")[:-1]),task:$task}' >> "$shunt_work/message" || return 1
  size=$(wc -c < "$shunt_work/message") || return 1
  ((size <= shunt_limit)) || { shunt_error 'Scout request exceeds the size limit'; return 1; }
  SHUNT_TASK_MODE=scout SHUNT_PROJECT_ROOT=$project shunt_invoke "$backend" "$model" scout || return 1
  size=$(wc -c < "$shunt_work/answer") || return 1
  ((size <= shunt_limit)) || { shunt_error 'Scout answer exceeds the size limit'; return 1; }
  cat "$shunt_work/answer"
}
