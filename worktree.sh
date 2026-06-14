# =========================
# DotVault Worktree Manager
# =========================
# Provides: `dotvault` CLI for managing git worktrees
# Source this in your shell config alongside other dotvault files

DOTVAULT_DIR="$HOME/.dotvault"
DOTVAULT_CONFIG="$DOTVAULT_DIR/config.json"

# =========================
# OS Detection
# =========================

_dv_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "other" ;;
  esac
}

# =========================
# Utilities
# =========================

_dv_die() {
  echo "Error: $1" >&2
  exit 1
}

_dv_warn() {
  echo "Warning: $1" >&2
}

_dv_info() {
  echo "= $1"
}

_dv_ensure_config() {
  if [ ! -f "$DOTVAULT_CONFIG" ]; then
    mkdir -p "$DOTVAULT_DIR"
    cat > "$DOTVAULT_CONFIG" <<'EOF'
{
  "repos": {},
  "defaults": {
    "base_branch": "main",
    "env_file": null,
    "init_commands": [],
    "opencode_cmd": "opencode"
  }
}
EOF
    _dv_info "Created $DOTVAULT_CONFIG"
  fi
}

# =========================
# JSON Config Helpers (via Python)
# =========================

_dv_config_get() {
  local key="$1"
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
keys = '$key'.split('.')
for k in keys:
    if isinstance(d, dict) and k in d:
        d = d[k]
    else:
        sys.exit(1)
if isinstance(d, list):
    for item in d:
        print(item)
elif d is None:
    pass
else:
    print(d)
" 2>/dev/null
}

_dv_config_set() {
  local key="$1"
  local value="$2"
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
keys = '$key'.split('.')
target = d
for k in keys[:-1]:
    target = target.setdefault(k, {})
try:
    target[keys[-1]] = json.loads('$value')
except (json.JSONDecodeError, ValueError):
    target[keys[-1]] = '$value'
with open('$DOTVAULT_CONFIG', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
}

_dv_config_append() {
  local key="$1"
  local value="$2"
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
keys = '$key'.split('.')
target = d
for k in keys[:-1]:
    target = target.setdefault(k, {})
arr = target.get(keys[-1], [])
arr.append('$value')
target[keys[-1]] = arr
with open('$DOTVAULT_CONFIG', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
}

# =========================
# Repo Name List
# =========================

_dv_get_repo_names() {
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
for name in d.get('repos', {}):
    print(name)
" 2>/dev/null
}

_dv_get_repo_paths() {
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
for name, info in d.get('repos', {}).items():
    print(name + '|' + info.get('path', ''))
" 2>/dev/null
}

# =========================
# Interactive Picker
# =========================

_dv_select_repo() {
  # Get list from python to avoid shell array indexing issues
  local repo_data
  repo_data=$(python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
repos = d.get('repos', {})
if not repos:
    print('__EMPTY__')
    sys.exit(0)
for i, (name, info) in enumerate(sorted(repos.items()), 1):
    print('%d|%s|%s' % (i, name, info.get('path', '')))
" 2>/dev/null)

  if [ -z "$repo_data" ] || [ "$repo_data" = "__EMPTY__" ]; then
    _dv_die "No repos registered. Run: dotvault repo add <name> <path>"
  fi

  # Build arrays using a temp file approach for cross-shell compatibility
  local tmpfile
  tmpfile=$(mktemp /tmp/dv_repos_XXXXXX)
  printf '%s\n' "$repo_data" > "$tmpfile"

  local count
  count=$(wc -l < "$tmpfile" | tr -d ' ')

  if [ "$count" -eq 1 ]; then
    IFS='|' read -r _ SELECTED_REPO SELECTED_REPO_PATH < "$tmpfile"
    rm -f "$tmpfile"
    _dv_info "Using repo: $SELECTED_REPO ($SELECTED_REPO_PATH)"
    return 0
  fi

  echo "Select a repo:"
  while IFS='|' read -r num rname rpath; do
    [ -z "$num" ] && continue
    printf "  %d) %s  (%s)\n" "$num" "$rname" "$rpath"
  done < "$tmpfile"

  printf "Enter choice [1-%d] (or name): " "$count"
  read -r choice

  if [ -z "$choice" ]; then
    rm -f "$tmpfile"
    _dv_die "No repo selected."
  fi

  # Check if choice is a number
  if [ "$choice" -eq "$choice" ] 2>/dev/null; then
    while IFS='|' read -r num rname rpath; do
      if [ "$num" = "$choice" ]; then
        SELECTED_REPO="$rname"
        SELECTED_REPO_PATH="$rpath"
        rm -f "$tmpfile"
        return 0
      fi
    done < "$tmpfile"
  else
    # Match by name
    while IFS='|' read -r num rname rpath; do
      if [ "$rname" = "$choice" ]; then
        SELECTED_REPO="$rname"
        SELECTED_REPO_PATH="$rpath"
        rm -f "$tmpfile"
        return 0
      fi
    done < "$tmpfile"
  fi

  rm -f "$tmpfile"
  _dv_die "Invalid selection: $choice"
}

_dv_select_worktree() {
  local repo="$1"
  local wt_dir="$DOTVAULT_DIR/worktrees/$repo"

  if [ ! -d "$wt_dir" ]; then
    _dv_die "No worktrees found for repo: $repo"
  fi

  # Build list via temp file for cross-shell compatibility
  local tmpfile
  tmpfile=$(mktemp /tmp/dv_wts_XXXXXX)
  local count=0

  for d in "$wt_dir"/*/; do
    [ ! -d "$d" ] && continue
    count=$((count + 1))
    local wt_name
    wt_name=$(basename "$d")
    local meta="$d/.meta.json"
    local prompt_text=""
    if [ -f "$meta" ]; then
      prompt_text=$(python3 -c "import json; print(json.load(open('$meta')).get('prompt',''))" 2>/dev/null)
    fi
    printf '%d|%s|%s\n' "$count" "$wt_name" "$prompt_text" >> "$tmpfile"
  done

  if [ "$count" -eq 0 ]; then
    rm -f "$tmpfile"
    _dv_die "No worktrees found for repo: $repo"
  fi

  echo "Select a worktree for '$repo':"
  while IFS='|' read -r num wname wprompt; do
    [ -z "$num" ] && continue
    printf "  %d) %s" "$num" "$wname"
    [ -n "$wprompt" ] && printf "  — %s" "$wprompt"
    printf "\n"
  done < "$tmpfile"

  printf "Enter choice [1-%d]: " "$count"
  read -r choice

  if [ -z "$choice" ]; then
    rm -f "$tmpfile"
    _dv_die "No worktree selected."
  fi

  if [ "$choice" -eq "$choice" ] 2>/dev/null; then
    while IFS='|' read -r num wname wprompt; do
      if [ "$num" = "$choice" ]; then
        SELECTED_WORKTREE="$wname"
        SELECTED_WORKTREE_PATH="$wt_dir/$wname"
        rm -f "$tmpfile"
        return 0
      fi
    done < "$tmpfile"
  else
    while IFS='|' read -r num wname wprompt; do
      if [ "$wname" = "$choice" ]; then
        SELECTED_WORKTREE="$wname"
        SELECTED_WORKTREE_PATH="$wt_dir/$wname"
        rm -f "$tmpfile"
        return 0
      fi
    done < "$tmpfile"
  fi

  rm -f "$tmpfile"
  _dv_die "Invalid selection: $choice"
}

# =========================
# Subcommand: repo
# =========================

_dv_repo() {
  local cmd="${1:-help}"; shift 2>/dev/null
  case "$cmd" in
    add) _dv_repo_add "$@" ;;
    remove|rm) _dv_repo_remove "$@" ;;
    list|ls) _dv_repo_list "$@" ;;
    config) _dv_repo_config "$@" ;;
    *) echo "Usage: dotvault repo <add|remove|list|config> [args...]"; return 1 ;;
  esac
}

_dv_repo_add() {
  local name="" repo_path="" base_branch="" env_file="" opencode_cmd=""
  local init_cmds=()

  # Parse args
  while [ $# -gt 0 ]; do
    case "$1" in
      --base-branch) base_branch="$2"; shift 2 ;;
      --env-file) env_file="$2"; shift 2 ;;
      --opencode-cmd) opencode_cmd="$2"; shift 2 ;;
      --init-commands) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do init_cmds+=("$1"); shift; done ;;
      *)
        if [ -z "$name" ]; then
          name="$1"; shift
        elif [ -z "$repo_path" ]; then
          repo_path="$1"; shift
        else
          _dv_die "Unknown argument: $1"
        fi
        ;;
    esac
  done

  # Interactive prompts for missing args
  if [ -z "$name" ]; then
    printf "Enter repo name: "; read -r name
  fi
  if [ -z "$repo_path" ]; then
    printf "Enter repo path: "; read -r repo_path
  fi
  repo_path="${repo_path/#\~/$HOME}"
  repo_path="$(cd "$repo_path" 2>/dev/null && pwd)" || _dv_die "Invalid path: $repo_path"
  [ -z "$base_branch" ] && { printf "Base branch [main]: "; read -r base_branch; base_branch="${base_branch:-main}"; }
  [ -z "$env_file" ] && { printf "Env file [.env] (leave empty to skip): "; read -r env_file; }
  if [ ${#init_cmds[@]} -eq 0 ]; then
    printf "Init commands (comma-separated, leave empty to skip): "; read -r cmds_str
    if [ -n "$cmds_str" ]; then
      IFS=',' read -r -a init_cmds <<< "$cmds_str"
    fi
  fi
  [ -z "$opencode_cmd" ] && { printf "OpenCode command [opencode]: "; read -r opencode_cmd; opencode_cmd="${opencode_cmd:-opencode}"; }

  # Check if repo already exists
  local existing_path
  existing_path=$(_dv_config_get "repos.$name.path" 2>/dev/null)
  if [ -n "$existing_path" ]; then
    _dv_die "Repo '$name' already exists (path: $existing_path). Use 'dotvault repo config' to modify."
  fi

  # Write to config
  _dv_config_set "repos.$name.path" "$repo_path"
  _dv_config_set "repos.$name.base_branch" "$base_branch"
  if [ -n "$env_file" ]; then
    _dv_config_set "repos.$name.env_file" "$env_file"
  else
    _dv_config_set "repos.$name.env_file" null
  fi
  _dv_config_set "repos.$name.opencode_cmd" "$opencode_cmd"

  # Clear init_commands first, then add
  _dv_config_set "repos.$name.init_commands" "[]"
  for cmd in "${init_cmds[@]}"; do
    local trimmed
    trimmed=$(echo "$cmd" | xargs)
    [ -n "$trimmed" ] && _dv_config_append "repos.$name.init_commands" "$trimmed"
  done

  _dv_info "Repo '$name' registered ($repo_path)"
}

_dv_repo_remove() {
  local name="$1"
  if [ -z "$name" ]; then
    # Interactive selection
    _dv_select_repo
    name="$SELECTED_REPO"
  fi
  printf "Remove repo '%s'? This does NOT delete the repo itself. [y/N]: " "$name"
  read -r confirm
  [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { _dv_info "Aborted."; return 0; }
  _dv_config_set "repos.$name" "__DELETE__"
  python3 -c "
import json
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
d['repos'].pop('$name', None)
with open('$DOTVAULT_CONFIG', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
  _dv_info "Repo '$name' removed."
}

_dv_repo_list() {
  python3 -c "
import json, sys
with open('$DOTVAULT_CONFIG') as f:
    d = json.load(f)
repos = d.get('repos', {})
if not repos:
    print('No repos registered.')
    sys.exit(0)
print('%-20s %-50s %-15s %-10s' % ('NAME', 'PATH', 'BRANCH', 'ENV'))
print('-' * 95)
for name, info in sorted(repos.items()):
    p = info.get('path', '-') or '-'
    b = info.get('base_branch', 'main') or 'main'
    e = info.get('env_file', '-') or '-'
    print('%-20s %-50s %-15s %-10s' % (name, p, b, e))
"
}

_dv_repo_config() {
  local name="$1" key="$2" value="$3"
  if [ -z "$name" ] || [ -z "$key" ]; then
    echo "Usage: dotvault repo config <name> <key> [value]"
    echo "Keys: path, base_branch, env_file, opencode_cmd, init_commands"
    return 1
  fi
  if [ -z "$value" ]; then
    local result
    result=$(_dv_config_get "repos.$name.$key")
    if [ -z "$result" ]; then
      echo "(not set)"
    else
      echo "$result"
    fi
  else
    _dv_config_set "repos.$name.$key" "$value"
    _dv_info "repos.$name.$key = $value"
  fi
}

# =========================
# Subcommand: worktree
# =========================

_dv_worktree() {
  local cmd="${1:-help}"; shift 2>/dev/null
  case "$cmd" in
    create) _dv_worktree_create "$@" ;;
    list|ls) _dv_worktree_list "$@" ;;
    delete|rm) _dv_worktree_delete "$@" ;;
    prune) _dv_worktree_prune "$@" ;;
    resume) _dv_worktree_resume "$@" ;;
    *) echo "Usage: dotvault worktree <create|list|delete|prune|resume> [args...]"; return 1 ;;
  esac
}

_dv_worktree_create() {
  local name="" prompt="" repo_flag="" FORCE=""

  # Parse args
  while [ $# -gt 0 ]; do
    case "$1" in
      --prompt) prompt="$2"; shift 2 ;;
      --repo) repo_flag="$2"; shift 2 ;;
      --force) FORCE=1; shift ;;
      *)
        if [ -z "$name" ]; then
          name="$1"; shift
        else
          _dv_die "Unknown argument: $1"
        fi
        ;;
    esac
  done

  [ -z "$name" ] && _dv_die "Missing worktree name."
  [ -z "$prompt" ] && _dv_die "Missing prompt. Use --prompt \"your task description\""

  # Select repo
  if [ -n "$repo_flag" ]; then
    local rp
    rp=$(_dv_config_get "repos.$repo_flag.path")
    [ -z "$rp" ] && _dv_die "Repo '$repo_flag' not found."
    SELECTED_REPO="$repo_flag"
    SELECTED_REPO_PATH="$rp"
  else
    _dv_select_repo
  fi

  local repo="$SELECTED_REPO"
  local repo_path="$SELECTED_REPO_PATH"
  local wt_path="$DOTVAULT_DIR/worktrees/$repo/$name"
  local base_branch env_file init_cmds opencode_cmd

  base_branch=$(_dv_config_get "repos.$repo.base_branch")
  env_file=$(_dv_config_get "repos.$repo.env_file")
  opencode_cmd=$(_dv_config_get "repos.$repo.opencode_cmd")
  base_branch="${base_branch:-main}"
  opencode_cmd="${opencode_cmd:-opencode}"

  # Collect init_commands
  local cmds=()
  while IFS= read -r line; do
    [ -n "$line" ] && cmds+=("$line")
  done < <(_dv_config_get "repos.$repo.init_commands")

  # Check worktree doesn't already exist
  if [ -d "$wt_path" ]; then
    _dv_die "Worktree '$name' already exists at $wt_path"
  fi

  # Check git status
  if ! git -C "$repo_path" diff --quiet HEAD 2>/dev/null; then
    if [ -n "$FORCE" ]; then
      _dv_warn "Stashing uncommitted changes..."
      git -C "$repo_path" stash push -m "dotvault: auto-stash before worktree $name"
    else
      _dv_die "Uncommitted changes in $repo_path. Commit, stash, or use --force."
    fi
  fi

  # Step 1: Fetch
  _dv_info "Fetching origin..."
  git -C "$repo_path" fetch origin 2>/dev/null || _dv_warn "Fetch failed (continuing...)"

  # Step 2: Checkout base branch and pull
  _dv_info "Checking out $base_branch and pulling..."
  git -C "$repo_path" checkout "$base_branch" 2>/dev/null || _dv_warn "Could not checkout $base_branch"
  git -C "$repo_path" pull 2>/dev/null || _dv_warn "Pull failed (continuing...)"

  # Step 3: Create worktree
  _dv_info "Creating worktree: $wt_path"
  mkdir -p "$DOTVAULT_DIR/worktrees/$repo"
  git -C "$repo_path" worktree add "$wt_path" -b "$name" 2>/dev/null || {
    # Branch might exist, try without -b
    git -C "$repo_path" worktree add "$wt_path" "$name" 2>/dev/null || {
      # Branch doesn't exist locally, might need to create
      git -C "$repo_path" branch "$name" "$base_branch" 2>/dev/null
      git -C "$repo_path" worktree add "$wt_path" "$name" 2>/dev/null || _dv_die "Failed to create worktree. Branch '$name' may already exist and be checked out elsewhere."
    }
  }

  # Step 4: Copy env file
  if [ -n "$env_file" ] && [ "$env_file" != "null" ]; then
    local env_src="$repo_path/$env_file"
    if [ -f "$env_src" ]; then
      cp "$env_src" "$wt_path/$env_file"
      _dv_info "Copied $env_file"
    elif [ -d "$env_src" ]; then
      cp -r "$env_src" "$wt_path/$env_file"
      _dv_info "Copied $env_file/ (directory)"
    else
      _dv_warn "$env_file not found in $repo_path (skipping)"
    fi
  fi

  # Step 5: Init commands
  if [ ${#cmds[@]} -gt 0 ]; then
    _dv_info "Running init_commands in worktree..."
    for c in "${cmds[@]}"; do
      trimmed_c=$(echo "$c" | xargs)
      [ -z "$trimmed_c" ] && continue
      printf "  -> %s\n" "$trimmed_c"
      (cd "$wt_path" && eval "$trimmed_c") || _dv_warn "Command failed: $trimmed_c"
    done
  fi

  # Step 6: Write .meta.json
  local created_at
  created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  export _DV_META_PROMPT="$prompt"
  python3 -c "
import json, os
meta = {
    'name': '$name',
    'branch': '$name',
    'repo': '$repo',
    'prompt': os.environ.get('_DV_META_PROMPT', ''),
    'created_at': '$created_at',
    'sessions': []
}
with open('$wt_path/.meta.json', 'w') as f:
    json.dump(meta, f, indent=2)
    f.write('\n')
"
  unset _DV_META_PROMPT
  _dv_info "Worktree '$name' created for repo '$repo'"

  # Step 7: Open VSCode with opencode
  _dv_open_worktree "$wt_path" "$prompt" "$opencode_cmd"
}

# =========================
# VSCode + OpenCode Integration
# =========================

_dv_write_tasks_json() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"
  mkdir -p "$wt_path/.vscode"
  export _DV_TASK_PROMPT="$prompt"
  export _DV_TASK_CMD="$opencode_cmd"
  python3 -c "
import json, os
task = {
    'version': '2.0.0',
    'tasks': [{
        'label': 'OpenCode',
        'type': 'shell',
        'command': os.environ['_DV_TASK_CMD'] + ' --prompt ' + json.dumps(os.environ.get('_DV_TASK_PROMPT', '')),
        'presentation': {
            'focus': True,
            'panel': 'new',
            'reveal': 'always',
            'echo': True,
            'showReuseMessage': False,
            'clear': True
        },
        'problemMatcher': []
    }]
}
with open('$wt_path/.vscode/tasks.json', 'w') as f:
    json.dump(task, f, indent=2)
    f.write('\n')
"
  unset _DV_TASK_PROMPT _DV_TASK_CMD
}

_dv_open_worktree() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"

  _dv_write_tasks_json "$wt_path" "$prompt" "$opencode_cmd"

  # Check if opencode exists
  if ! command -v "$opencode_cmd" >/dev/null 2>&1; then
    _dv_warn "'$opencode_cmd' not found. Opening VSCode without opencode."
    if command -v code >/dev/null 2>&1; then
      code "$wt_path"
    fi
    return 0
  fi

  case "$(_dv_os)" in
    macos) _dv_open_vscode_macos "$wt_path" "$prompt" "$opencode_cmd" ;;
    linux) _dv_open_vscode_linux "$wt_path" "$prompt" "$opencode_cmd" ;;
    *)
      if command -v code >/dev/null 2>&1; then
        code "$wt_path"
        _dv_info "Run the OpenCode task in VSCode: Terminal > Run Task > OpenCode"
      fi
      ;;
  esac
}

# =========================
# macOS: VSCode + OpenCode
# =========================

_dv_open_vscode_macos() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"

  if ! command -v code >/dev/null 2>&1; then
    _dv_warn "VSCode 'code' command not found. Opening Terminal instead."
    _dv_open_terminal_macos "$wt_path" "$prompt" "$opencode_cmd"
    return 0
  fi

  _dv_info "Opening VSCode in worktree..."
  code "$wt_path"
  sleep 2

  # Write prompt to temp file for AppleScript to read
  local prompt_file
  prompt_file="/tmp/_dv_prompt_${$}.txt"
  printf '%s' "$prompt" > "$prompt_file"

  # Use osascript to toggle terminal and type command
  osascript \
    -e "set promptFile to \"$prompt_file\"" \
    -e "set opencodeCmd to \"$opencode_cmd\"" \
    -e "set promptText to read file promptFile" \
    -e 'tell application "Visual Studio Code" to activate' \
    -e 'delay 1.5' \
    -e 'tell application "System Events"' \
    -e '  tell process "Code"' \
    -e '    key code 50 using {control down}' \
    -e '    delay 1' \
    -e '    keystroke opencodeCmd & " --prompt " & quoted form of promptText' \
    -e '    keystroke return' \
    -e '  end tell' \
    -e 'end tell' > /dev/null 2>&1 &

  rm -f "$prompt_file"
  _dv_info "OpenCode launched in VSCode terminal."
}

_dv_open_terminal_macos() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"
  local prompt_file
  prompt_file="/tmp/_dv_prompt_${$}.txt"
  printf '%s' "$prompt" > "$prompt_file"

  osascript \
    -e "set wtPath to \"$wt_path\"" \
    -e "set promptFile to \"$prompt_file\"" \
    -e "set opencodeCmd to \"$opencode_cmd\"" \
    -e "set promptText to read file promptFile" \
    -e 'tell application "Terminal"' \
    -e '  activate' \
    -e '  do script "cd " & quoted form of wtPath & " && " & opencodeCmd & " --prompt " & quoted form of promptText' \
    -e 'end tell' > /dev/null 2>&1 &

  rm -f "$prompt_file"
  _dv_info "OpenCode launched in Terminal.app."
}

# =========================
# Linux: VSCode + OpenCode
# =========================

_dv_open_vscode_linux() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"

  if ! command -v code >/dev/null 2>&1; then
    _dv_warn "VSCode 'code' command not found. Opening terminal instead."
    _dv_open_terminal_linux "$wt_path" "$prompt" "$opencode_cmd"
    return 0
  fi

  _dv_info "Opening VSCode in worktree..."
  code "$wt_path"

  if command -v xdotool >/dev/null 2>&1; then
    sleep 2
    local prompt_file
    prompt_file="/tmp/_dv_prompt_${$}.txt"
    printf '%s' "$prompt" > "$prompt_file"

    # Focus VSCode, open integrated terminal (Ctrl+`), type command
    {
      sleep 2
      xdotool search --name "Visual Studio Code" windowactivate --sync 2>/dev/null
      xdotool key ctrl+grave
      sleep 1
      xdotool type "$opencode_cmd --prompt $(printf '%s' "$prompt" | sed "s/'/'\\\\''/g")"
      xdotool key Return
    } > /dev/null 2>&1 &
    rm -f "$prompt_file"
    _dv_info "OpenCode launched in VSCode terminal."
  else
    _dv_info "Run the OpenCode task in VSCode: Terminal > Run Task > OpenCode"
    _dv_info "Need xdotool? Install: sudo apt install xdotool (Debian) or sudo dnf install xdotool (Fedora)"
  fi
}

_dv_open_terminal_linux() {
  local wt_path="$1"
  local prompt="$2"
  local opencode_cmd="$3"

  for term in gnome-terminal konsole xterm x-terminal-emulator; do
    if command -v "$term" >/dev/null 2>&1; then
      case "$term" in
        gnome-terminal)
          gnome-terminal -- bash -c "cd '$wt_path' && exec $opencode_cmd --prompt '$prompt'; exec bash"
          ;;
        konsole)
          konsole --workdir "$wt_path" -e bash -c "$opencode_cmd --prompt '$prompt'; exec bash"
          ;;
        xterm)
          xterm -e bash -c "cd '$wt_path' && $opencode_cmd --prompt '$prompt'; exec bash"
          ;;
        x-terminal-emulator)
          x-terminal-emulator -e bash -c "cd '$wt_path' && $opencode_cmd --prompt '$prompt'; exec bash"
          ;;
      esac
      _dv_info "OpenCode launched in $term."
      return 0
    fi
  done
  _dv_warn "No terminal emulator found. cd into $wt_path and run: $opencode_cmd --prompt \"$prompt\""
}

# =========================
# worktree: list
# =========================

_dv_worktree_list() {
  local repo_filter=""
  [ $# -gt 0 ] && [ "${1#--}" = "$1" ] && repo_filter="$1"

  local repos=()
  while IFS= read -r name; do
    [ -n "$name" ] && repos+=("$name")
  done < <(_dv_get_repo_names)

  if [ ${#repos[@]} -eq 0 ]; then
    echo "No repos registered."
    return 0
  fi

  for repo in "${repos[@]}"; do
    [ -n "$repo_filter" ] && [ "$repo" != "$repo_filter" ] && continue
    local wt_dir="$DOTVAULT_DIR/worktrees/$repo"

    echo ""
    printf "\033[1m%s:\033[0m\n" "$repo"

    if [ ! -d "$wt_dir" ]; then
      echo "  (no worktrees)"
      continue
    fi

    # Use find for cross-shell compat (avoids zsh glob nomatch error)
    local wt_list
    wt_list=$(find "$wt_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    if [ -z "$wt_list" ]; then
      echo "  (no worktrees)"
      continue
    fi

    printf '%s' "$wt_list" | while IFS= read -r wt; do
      [ -z "$wt" ] && continue
      local wt_name
      wt_name=$(basename "$wt")
      local meta="$wt/.meta.json"
      local prompt_text="" created_at="" sessions_count="0"

      if [ -f "$meta" ]; then
        IFS='|' read -r prompt_text created_at sessions_count <<< "$(python3 -c "
import json
try:
    m = json.load(open('$meta'))
    p = m.get('prompt', '')
    c = m.get('created_at', '')
    s = str(len(m.get('sessions', [])))
    print(p + '|' + c + '|' + s)
except:
    print('||0')
")"
      fi

      # Truncate prompt to 50 chars
      local display_prompt="$prompt_text"
      if [ ${#display_prompt} -gt 50 ]; then
        display_prompt="${display_prompt:0:47}..."
      fi

      printf "  \033[36m%-20s\033[0m %-50s %s  %s session(s)\n" "$wt_name" "$display_prompt" "$created_at" "$sessions_count"
    done
  done
  echo ""
}

# =========================
# worktree: delete
# =========================

_dv_worktree_delete() {
  local target_name="$1"

  # Select repo
  _dv_select_repo
  local repo="$SELECTED_REPO"
  local repo_path="$SELECTED_REPO_PATH"
  local wt_dir="$DOTVAULT_DIR/worktrees/$repo"

  if [ -n "$target_name" ]; then
    SELECTED_WORKTREE="$target_name"
    SELECTED_WORKTREE_PATH="$wt_dir/$target_name"
    [ ! -d "$SELECTED_WORKTREE_PATH" ] && _dv_die "Worktree '$target_name' not found."
  else
    _dv_select_worktree "$repo"
  fi

  local name="$SELECTED_WORKTREE"
  local wt_path="$SELECTED_WORKTREE_PATH"

  printf "Delete worktree '%s/%s'? (rm dir + git branch) [y/N]: " "$repo" "$name"
  read -r confirm
  [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { _dv_info "Aborted."; return 0; }

  # Remove git worktree
  git -C "$repo_path" worktree remove "$wt_path" 2>/dev/null || {
    _dv_warn "git worktree remove failed (might be dirty). Forcing..."
    git -C "$repo_path" worktree remove --force "$wt_path" 2>/dev/null || true
  }

  # Delete branch
  git -C "$repo_path" branch -D "$name" 2>/dev/null || _dv_warn "Branch '$name' not found or could not be deleted."

  # Remove directory
  rm -rf "$wt_path"
  _dv_info "Worktree '$name' deleted."
}

# =========================
# worktree: prune
# =========================

_dv_worktree_prune() {
  local repo_flag=""
  [ "$1" = "--repo" ] && { repo_flag="$2"; shift 2; }

  local repos=()
  if [ -n "$repo_flag" ]; then
    repos=("$repo_flag")
  else
    while IFS= read -r name; do
      [ -n "$name" ] && repos+=("$name")
    done < <(_dv_get_repo_names)
  fi

  for repo in "${repos[@]}"; do
    local repo_path
    repo_path=$(_dv_config_get "repos.$repo.path")
    [ -z "$repo_path" ] && continue

    local wt_dir="$DOTVAULT_DIR/worktrees/$repo"
    [ ! -d "$wt_dir" ] && continue

    local wt_list
    wt_list=$(find "$wt_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    [ -z "$wt_list" ] && continue

    printf '%s' "$wt_list" | while IFS= read -r wt; do
      [ -z "$wt" ] && continue
      local name
      name=$(basename "$wt")

      # Check if branch still exists remotely (try local too)
      if ! git -C "$repo_path" show-ref --verify --quiet "refs/heads/$name" 2>/dev/null && \
         ! git -C "$repo_path" show-ref --verify --quiet "refs/remotes/origin/$name" 2>/dev/null; then
        printf "Prune '%s/%s'? Branch no longer exists. [y/N]: " "$repo" "$name"
        read -r confirm
        [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

        git -C "$repo_path" worktree remove --force "$wt" 2>/dev/null || true
        rm -rf "$wt"
        _dv_info "Pruned: $repo/$name"
      fi
    done
  done
}

# =========================
# worktree: resume
# =========================

_dv_worktree_resume() {
  local target_name="$1"

  _dv_select_repo
  local repo="$SELECTED_REPO"
  local repo_path="$SELECTED_REPO_PATH"
  local wt_dir="$DOTVAULT_DIR/worktrees/$repo"

  if [ -n "$target_name" ]; then
    SELECTED_WORKTREE="$target_name"
    SELECTED_WORKTREE_PATH="$wt_dir/$target_name"
    [ ! -d "$SELECTED_WORKTREE_PATH" ] && _dv_die "Worktree '$target_name' not found for repo '$repo'."
  else
    _dv_select_worktree "$repo"
  fi

  local wt_path="$SELECTED_WORKTREE_PATH"
  local meta="$wt_path/.meta.json"

  if [ ! -f "$meta" ]; then
    _dv_die "No .meta.json found in $wt_path. Cannot resume."
  fi

  # Read meta
  local prompt
  prompt=$(python3 -c "import json; print(json.load(open('$meta')).get('prompt',''))" 2>/dev/null)
  local opencode_cmd
  opencode_cmd=$(_dv_config_get "repos.$repo.opencode_cmd")
  opencode_cmd="${opencode_cmd:-opencode}"

  _dv_info "Resuming worktree '$SELECTED_WORKTREE' for repo '$repo'"
  [ -n "$prompt" ] && echo "  Prompt: $prompt"

  _dv_open_worktree "$wt_path" "$prompt" "$opencode_cmd"
}

# =========================
# Subcommand: config
# =========================

_dv_config() {
  local key="$1" value="$2"

  if [ -z "$key" ]; then
    echo "Global defaults:"
    echo "  base_branch:   $(_dv_config_get defaults.base_branch)"
    echo "  env_file:      $(_dv_config_get defaults.env_file)"
    echo "  opencode_cmd:  $(_dv_config_get defaults.opencode_cmd)"
    echo ""
    echo "Usage: dotvault config <key> [value]"
    echo "Keys: base_branch, env_file, opencode_cmd"
    return 0
  fi

  if [ -z "$value" ]; then
    _dv_config_get "defaults.$key"
  else
    _dv_config_set "defaults.$key" "$value"
    _dv_info "defaults.$key = $value"
  fi
}

# =========================
# Menu Interface
# =========================

_dv_menu_header() {
  clear 2>/dev/null || true
  echo "╔═══════════════════════════════════════════╗"
  echo "║             dotvault — v1.0               ║"
  echo "║     Worktree manager for your repos       ║"
  echo "╚═══════════════════════════════════════════╝"
  echo ""
}

_dv_menu() {
  while true; do
    _dv_menu_header
    echo "  What would you like to do?"
    echo ""
    echo "   1)  Add a repo"
    echo "   2)  Remove a repo"
    echo "   3)  List repos"
    echo "   4)  Create a worktree"
    echo "   5)  List worktrees"
    echo "   6)  Delete a worktree"
    echo "   7)  Prune worktrees"
    echo "   8)  Resume a worktree"
    echo "   9)  Configure defaults"
    echo "   10) Help"
    echo "   0)  Exit"
    echo ""
    printf "  Enter choice [0-10]: "
    read -r menu_choice

    case "$menu_choice" in
      1) _dv_repo_add ;;
      2) _dv_repo_remove ;;
      3) _dv_repo_list ;;
      4) _dv_worktree_create_interactive ;;
      5) _dv_worktree_list ;;
      6) _dv_worktree_delete ;;
      7) _dv_worktree_prune ;;
      8) _dv_worktree_resume ;;
      9) _dv_config_interactive ;;
      10) _dv_help ;;
      0)
        echo "  Goodbye."
        break
        ;;
      *)
        echo "  Invalid choice. Press Enter to continue..."
        read -r _
        ;;
    esac

    if [ "$menu_choice" != "0" ]; then
      echo ""
      printf "  Press Enter to return to menu..."
      read -r _
    fi
  done
}

_dv_worktree_create_interactive() {
  _dv_ensure_config
  printf "  Worktree name: "
  read -r wt_name
  [ -z "$wt_name" ] && { _dv_warn "Name required."; return 1; }
  printf "  Task prompt: "
  read -r wt_prompt
  [ -z "$wt_prompt" ] && { _dv_warn "Prompt required."; return 1; }
  _dv_worktree_create "$wt_name" --prompt "$wt_prompt"
}

_dv_config_interactive() {
  _dv_ensure_config
  echo ""
  echo "  Current defaults:"
  echo "    base_branch:  $(_dv_config_get defaults.base_branch)"
  echo "    env_file:     $(_dv_config_get defaults.env_file)"
  echo "    opencode_cmd: $(_dv_config_get defaults.opencode_cmd)"
  echo ""
  printf "  Which default to change? (base_branch/env_file/opencode_cmd, empty to skip): "
  read -r cfg_key
  [ -z "$cfg_key" ] && return 0
  printf "  New value for '%s': " "$cfg_key"
  read -r cfg_val
  [ -z "$cfg_val" ] && return 0
  _dv_config_set "defaults.$cfg_key" "$cfg_val"
  _dv_info "defaults.$cfg_key = $cfg_value"
}

# =========================
# Help
# =========================

_dv_help() {
  echo ""
  echo "  dotvault is a worktree manager that helps you:"
  echo "    - Register repos you work on"
  echo "    - Create isolated worktrees for tasks"
  echo "    - Auto-setup env files and dependencies"
  echo "    - Open VSCode with your task prompt"
  echo "    - Resume worktrees later"
  echo ""
  echo "  Just run 'dotvault' (or 'dv') for the interactive menu."
}

# =========================
# Main Entry Point
# =========================

dotvault() {
  _dv_ensure_config

  if [ $# -eq 0 ]; then
    _dv_menu
    return 0
  fi

  # Direct command mode for scripting
  local cmd="$1"
  shift 2>/dev/null

  case "$cmd" in
    repo) _dv_repo "$@" ;;
    worktree|wt) _dv_worktree "$@" ;;
    config) _dv_config "$@" ;;
    help|--help|-h) _dv_help ;;
    *)
      echo "Unknown command: $cmd"
      echo "Run 'dotvault' with no arguments for the interactive menu."
      return 1
      ;;
  esac
}

# Convenience alias
alias dv='dotvault'
