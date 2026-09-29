#!/usr/bin/env bash

# git-delete-worktree
# External Git command script
# Save this file as 'git-delete-worktree' in your PATH (e.g., ~/bin/ or /usr/local/bin/)
# Make it executable: chmod +x git-delete-worktree

set -e  # Exit on any error

# Color definitions (only the ones we actually use)
# Reset
NC='\033[0m' # Text Reset

# Regular Colors (only the ones we use)
RED='\033[0;31m'    # Red
GREEN='\033[0;32m'  # Green
YELLOW='\033[0;33m' # Yellow

# Function to print colored messages (based on common.sh pattern)
message() {
  local exit_code=-1
  local color="${GREEN}"
  local text
  local newline_before=false
  local newline_after=false
  while [[ "$#" -gt 0 ]]; do
    case "${1}" in
    -m | --msg)
      text="${2}"
      shift 2
      ;;
    -n | --new-line)
      # Check if this is before or after the text
      if [[ -z "$text" ]]; then
        newline_before=true
      else
        newline_after=true
      fi
      shift
      ;;
    -e | --exit-code)
      exit_code="${2}"
      shift 2
      ;;
    -c | --color)
      color="${2}"
      shift 2
      ;;
    -z | --exit-on-zero)
      exit_on_zero=true
      exit_code=0
      shift
      ;;
    *)
      shift
      ;;
    esac
  done
  
  local output_text=""
  if [[ "$newline_before" == true ]]; then
    output_text="\n"
  fi
  output_text+="${color}${text}${NC}"
  if [[ "$newline_after" == true ]]; then
    output_text+="\n"
  fi
  
  if (exec </dev/tty); then
    echo -e "${output_text}" >/dev/tty
  else
    echo -e "${output_text}"
  fi
  if [[ "${exit_code}" -gt 0 ]]; then
    exit "${exit_code}"
  elif [[ "${exit_code}" -eq 0 ]] && [[ "$exit_on_zero" == true ]]; then
    exit 0
  fi
  return 0
}

# Function to show usage
show_usage() {
    message -m "Usage: git delete-worktree [worktree-name] [options]" -n
    echo ""
    echo "Delete both worktree folder and its associated local branch"
    echo ""
    echo "If no worktree name is provided, uses the current worktree."
    echo "Worktree name is the folder/directory name, not the full path."
    echo ""
    echo "Options:"
    echo "  -f, --force     Force deletion without confirmation"
    echo "  -h              Show this help message"
    echo "  -l, --list      List all available worktrees"
    echo ""
    echo "The script asks the remote whether the upstream branch still exists"
    echo "(git ls-remote). It does not fetch or update remote-tracking refs."
    echo "If that branch is missing, the local branch is ahead of it, or the"
    echo "remote cannot be checked, deletion asks for an extra confirmation."
    echo "--force skips that prompt."
    echo ""
    echo "Examples:"
    echo "  git delete-worktree                    # Delete current worktree and branch"
    echo "  git delete-worktree feature-branch     # Delete worktree named 'feature-branch'"
    echo "  git delete-worktree my-feature         # Delete worktree named 'my-feature'"
    echo "  git delete-worktree feature-123 -f     # Delete without confirmation"
    echo "  git delete-worktree --list             # List all available worktrees"
}

commit_noun() {
    if [[ "$1" -eq 1 ]]; then
        echo "commit"
    else
        echo "commits"
    fi
}

remote_heads() {
    local remote="$1"
    local key status_var data_var data
    key=$(printf '%s' "$remote" | tr -c 'A-Za-z0-9' '_')
    status_var="REMOTE_HEADS_${key}_STATUS"
    data_var="REMOTE_HEADS_${key}_DATA"
    if [[ -n "${!status_var:-}" ]]; then
        REMOTE_HEADS_STATUS="${!status_var}"
        REMOTE_HEADS_DATA="${!data_var:-}"
        return 0
    fi
    if data=$(GIT_TERMINAL_PROMPT=0 git ls-remote --heads "$remote" 2>/dev/null); then
        printf -v "$status_var" '%s' "ok"
        printf -v "$data_var" '%s' "$data"
    else
        printf -v "$status_var" '%s' "fail"
        printf -v "$data_var" '%s' ""
    fi
    REMOTE_HEADS_STATUS="${!status_var}"
    REMOTE_HEADS_DATA="${!data_var:-}"
}

remote_branch_state() {
    local remote="$1"
    local head="$2"
    local sha ref
    REMOTE_BRANCH_SHA=""
    remote_heads "$remote"
    if [[ "$REMOTE_HEADS_STATUS" != "ok" ]]; then
        REMOTE_BRANCH="unknown"
        return 0
    fi
    REMOTE_BRANCH="no"
    while IFS=$'\t' read -r sha ref; do
        if [[ "$ref" == "refs/heads/${head}" ]]; then
            REMOTE_BRANCH="yes"
            REMOTE_BRANCH_SHA="$sha"
            return 0
        fi
    done <<< "$REMOTE_HEADS_DATA"
    return 0
}

commits_not_on_other_remotes() {
    local branch="$1"
    local stale_ref="$2"
    local refs=()
    local ref
    while IFS= read -r ref; do
        if [[ -z "$ref" || "$ref" == "$stale_ref" ]]; then
            continue
        fi
        refs+=("$ref")
    done < <(git for-each-ref --format='%(refname)' refs/remotes)
    if [[ ${#refs[@]} -eq 0 ]]; then
        git rev-list --count "$branch"
    else
        git rev-list --count "$branch" --not "${refs[@]}"
    fi
}

refresh_from_remote() {
    local branch="$1"
    local short="$2"
    local remote_name merge_ref head_name stale_ref

    remote_name=$(git config --get "branch.${branch}.remote" 2>/dev/null || true)
    merge_ref=$(git config --get "branch.${branch}.merge" 2>/dev/null || true)
    if [[ -z "$remote_name" || -z "$merge_ref" ]]; then
        remote_name="${short%%/*}"
        head_name="${short#*/}"
    else
        head_name="${merge_ref#refs/heads/}"
    fi
    if [[ -z "$remote_name" || "$remote_name" == "." || -z "$head_name" ]]; then
        return 0
    fi

    remote_branch_state "$remote_name" "$head_name"
    stale_ref="refs/remotes/${remote_name}/${head_name}"

    if [[ "$REMOTE_BRANCH" == "unknown" ]]; then
        TRACK_CHECK_FAILED=1
        TRACK_DISPLAY="${TRACK_DISPLAY} (could not check ${remote_name})"
        return 0
    fi

    if [[ "$REMOTE_BRANCH" == "no" ]]; then
        TRACK_ABSENT=1
        TRACK_AHEAD=0
        TRACK_BEHIND=0
        TRACK_STATE="gone"
        TRACK_UNIQUE=$(commits_not_on_other_remotes "$branch" "$stale_ref")
        if [[ "$TRACK_UNIQUE" -gt 0 ]]; then
            TRACK_DISPLAY="${short} (not on ${remote_name}, ${TRACK_UNIQUE} not on any remote)"
        else
            TRACK_DISPLAY="${short} (not on ${remote_name})"
        fi
        return 0
    fi

    if git cat-file -e "${REMOTE_BRANCH_SHA}^{commit}" >/dev/null 2>&1; then
        TRACK_AHEAD=$(git rev-list --count "${REMOTE_BRANCH_SHA}..${branch}")
        TRACK_BEHIND=$(git rev-list --count "${branch}..${REMOTE_BRANCH_SHA}")
        if [[ "$TRACK_AHEAD" -gt 0 && "$TRACK_BEHIND" -gt 0 ]]; then
            TRACK_STATE="diverged"
            TRACK_DISPLAY="${short} (ahead ${TRACK_AHEAD}, behind ${TRACK_BEHIND})"
        elif [[ "$TRACK_AHEAD" -gt 0 ]]; then
            TRACK_STATE="ahead"
            TRACK_DISPLAY="${short} (ahead ${TRACK_AHEAD})"
        elif [[ "$TRACK_BEHIND" -gt 0 ]]; then
            TRACK_STATE="behind"
            TRACK_DISPLAY="${short} (behind ${TRACK_BEHIND})"
        else
            TRACK_STATE="synced"
            TRACK_DISPLAY="$short"
        fi
    else
        TRACK_TIP_MISSING=1
        TRACK_AHEAD=0
        TRACK_DISPLAY="${short} (on ${remote_name}; tip not fetched)"
    fi
}

branch_tracking() {
    local branch="$1"
    local short track

    TRACK_UPSTREAM=""
    TRACK_STATE="none"
    TRACK_AHEAD=0
    TRACK_BEHIND=0
    TRACK_UNIQUE=0
    TRACK_DISPLAY="-"
    TRACK_CHECK_FAILED=0
    TRACK_TIP_MISSING=0
    TRACK_ABSENT=0

    if [[ -z "$branch" || "$branch" == "(detached)" ]]; then
        return 0
    fi

    short=$(git for-each-ref --format='%(upstream:short)' "refs/heads/${branch}")
    track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/${branch}")

    if [[ -z "$short" ]]; then
        TRACK_UNIQUE=$(git rev-list --count "$branch" --not --remotes)
        if [[ "$TRACK_UNIQUE" -gt 0 ]]; then
            TRACK_DISPLAY="none (${TRACK_UNIQUE} not on any remote)"
        else
            TRACK_DISPLAY="none"
        fi
        return 0
    fi

    TRACK_UPSTREAM="$short"
    if [[ "$track" == "[gone]" ]]; then
        TRACK_STATE="gone"
        TRACK_UNIQUE=$(git rev-list --count "$branch" --not --remotes)
        if [[ "$TRACK_UNIQUE" -gt 0 ]]; then
            TRACK_DISPLAY="${short} (gone, ${TRACK_UNIQUE} not on any remote)"
        else
            TRACK_DISPLAY="${short} (gone)"
        fi
    elif [[ "$track" =~ ^\[ahead\ ([0-9]+),\ behind\ ([0-9]+)\]$ ]]; then
        TRACK_STATE="diverged"
        TRACK_AHEAD="${BASH_REMATCH[1]}"
        TRACK_BEHIND="${BASH_REMATCH[2]}"
        TRACK_DISPLAY="${short} (ahead ${TRACK_AHEAD}, behind ${TRACK_BEHIND})"
    elif [[ "$track" =~ ^\[ahead\ ([0-9]+)\]$ ]]; then
        TRACK_STATE="ahead"
        TRACK_AHEAD="${BASH_REMATCH[1]}"
        TRACK_DISPLAY="${short} (ahead ${TRACK_AHEAD})"
    elif [[ "$track" =~ ^\[behind\ ([0-9]+)\]$ ]]; then
        TRACK_STATE="behind"
        TRACK_BEHIND="${BASH_REMATCH[1]}"
        TRACK_DISPLAY="${short} (behind ${TRACK_BEHIND})"
    else
        TRACK_STATE="synced"
        TRACK_DISPLAY="$short"
    fi

    refresh_from_remote "$branch" "$short"
}

unpushed_warning() {
    UNPUSHED_WARN=""
    if [[ "$TRACK_ABSENT" -eq 1 && "$TRACK_UNIQUE" -gt 0 ]]; then
        if [[ "$TRACK_UNIQUE" -eq 1 ]]; then
            UNPUSHED_WARN="'${TRACK_UPSTREAM}' is not on the remote. '${BRANCH_NAME}' has 1 commit that is not on any remote."
        else
            UNPUSHED_WARN="'${TRACK_UPSTREAM}' is not on the remote. '${BRANCH_NAME}' has ${TRACK_UNIQUE} commits that are not on any remote."
        fi
    elif [[ "$TRACK_AHEAD" -gt 0 ]]; then
        UNPUSHED_WARN="'${BRANCH_NAME}' is ${TRACK_AHEAD} $(commit_noun "$TRACK_AHEAD") ahead of ${TRACK_UPSTREAM}. Those commits are not on that upstream."
        if [[ "$TRACK_CHECK_FAILED" -eq 1 ]]; then
            UNPUSHED_WARN="${UNPUSHED_WARN} Could not verify that the branch still exists on the remote."
        fi
    elif [[ "$TRACK_TIP_MISSING" -eq 1 ]]; then
        UNPUSHED_WARN="'${TRACK_UPSTREAM}' exists on the remote, but that commit is not in this repository, so unpushed work could not be checked."
    elif [[ "$TRACK_CHECK_FAILED" -eq 1 ]]; then
        UNPUSHED_WARN="Could not verify that '${TRACK_UPSTREAM}' still exists on the remote."
    elif [[ "$TRACK_STATE" == "none" || "$TRACK_STATE" == "gone" ]] && [[ "$TRACK_UNIQUE" -gt 0 ]]; then
        if [[ "$TRACK_UNIQUE" -eq 1 ]]; then
            UNPUSHED_WARN="'${BRANCH_NAME}' has 1 commit that is not on any remote."
        else
            UNPUSHED_WARN="'${BRANCH_NAME}' has ${TRACK_UNIQUE} commits that are not on any remote."
        fi
    fi
}

print_unpushed_warning() {
    unpushed_warning
    if [[ -z "$UNPUSHED_WARN" ]]; then
        return 0
    fi
    message -m "⚠ WARNING: ${UNPUSHED_WARN}" -c "$YELLOW"
    message -m "Deleting the local branch keeps them only in the reflog." -c "$YELLOW" -n
}

confirm_unpushed_commits() {
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    print_unpushed_warning
    if [[ -z "$UNPUSHED_WARN" ]]; then
        return 0
    fi
    read -p "Are you absolutely sure you want to delete '${BRANCH_NAME}'? Type 'yes' to confirm: " -r
    if [[ "$REPLY" != "yes" ]]; then
        message -m "Operation cancelled for safety" -c "$YELLOW" -z
    fi
}

# Function to list available worktrees
list_worktrees() {
    local exclude_worktree="$1"
    message -m "Available worktrees:" -n

    local worktrees=()
    local max_name_length=4
    local max_branch_length=6
    local max_upstream_length=8
    local current_name=""
    local current_path=""
    local current_branch=""

    flush_listed_worktree() {
        local upstream
        if [[ -z "$current_name" ]]; then
            return 0
        fi
        if [[ -n "$exclude_worktree" && "$current_name" == "$exclude_worktree" ]]; then
            current_name=""
            current_path=""
            current_branch=""
            return 0
        fi
        branch_tracking "$current_branch"
        upstream="$TRACK_DISPLAY"
        worktrees+=("${current_name}|${current_branch}|${upstream}|${current_path}")
        if [[ ${#current_name} -gt $max_name_length ]]; then
            max_name_length=${#current_name}
        fi
        if [[ ${#current_branch} -gt $max_branch_length ]]; then
            max_branch_length=${#current_branch}
        fi
        if [[ ${#upstream} -gt $max_upstream_length ]]; then
            max_upstream_length=${#upstream}
        fi
        current_name=""
        current_path=""
        current_branch=""
    }

    while IFS= read -r line; do
        if [[ $line == worktree* ]]; then
            flush_listed_worktree
            current_path="${line#worktree }"
            current_name=$(basename "$current_path")
            current_branch=""
        elif [[ $line == branch* ]] && [[ -n "$current_name" ]]; then
            current_branch="${line#branch refs/heads/}"
        elif [[ $line == HEAD* ]] && [[ -n "$current_name" ]]; then
            if [[ -z "$current_branch" ]]; then
                local head_ref="${line#HEAD }"
                if [[ "$head_ref" =~ ^[a-f0-9]{40}$ ]]; then
                    current_branch="(detached)"
                fi
            fi
        elif [[ -z "$line" ]] && [[ -n "$current_name" ]]; then
            flush_listed_worktree
        fi
    done < <(git worktree list --porcelain)

    flush_listed_worktree

    printf "  %-${max_name_length}s  %-${max_branch_length}s  %-${max_upstream_length}s  %s\n" "NAME" "BRANCH" "UPSTREAM" "PATH"
    printf "  %-${max_name_length}s  %-${max_branch_length}s  %-${max_upstream_length}s  %s\n" "$(printf '%*s' $max_name_length | tr ' ' '-')" "$(printf '%*s' $max_branch_length | tr ' ' '-')" "$(printf '%*s' $max_upstream_length | tr ' ' '-')" "$(printf '%*s' 50 | tr ' ' '-')"

    local worktree name branch upstream path
    for worktree in "${worktrees[@]}"; do
        IFS='|' read -r name branch upstream path <<< "$worktree"
        printf "  %-${max_name_length}s  %-${max_branch_length}s  %-${max_upstream_length}s  %s\n" "$name" "$branch" "$upstream" "$path"
    done
}

# Parse arguments
WORKTREE_NAME=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h)
            show_usage
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -l|--list)
            list_worktrees
            exit 0
            ;;
        -*)
            message -m "Error: Unknown option $1" -c "$RED"
            show_usage
            exit 1
            ;;
        *)
            if [[ -z "$WORKTREE_NAME" ]]; then
                WORKTREE_NAME="$1"
            else
                message -m "Error: Too many arguments" -c "$RED"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if we're in a Git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    message -m "Error: Not in a Git repository" -c "$RED" -e 1
fi

# If no worktree name provided, use current worktree name
if [[ -z "$WORKTREE_NAME" ]]; then
    CURRENT_WORKTREE_PATH=$(git rev-parse --show-toplevel)
    WORKTREE_NAME=$(basename "$CURRENT_WORKTREE_PATH")
    message -m "No worktree specified, using current worktree: $WORKTREE_NAME" -c "$YELLOW"
fi

# Find the full path for the worktree by name
WORKTREE_PATH=""
BRANCH_NAME=""
current_path=""
current_name=""
in_target_worktree=false
found_branch=false

while IFS= read -r line; do
    if [[ $line == worktree* ]]; then
        # Start of a new worktree entry
        current_path="${line#worktree }"
        current_name=$(basename "$current_path")
        in_target_worktree=false
        found_branch=false
        
        # Check if this is the worktree we're looking for
        if [[ "$current_name" == "$WORKTREE_NAME" ]]; then
            in_target_worktree=true
            WORKTREE_PATH="$current_path"
        fi
    elif [[ $line == branch* ]] && [[ "$in_target_worktree" == true ]]; then
        # Found the branch for our target worktree
        BRANCH_NAME="${line#branch refs/heads/}"
        found_branch=true
        break
    elif [[ $line == bare* ]] && [[ "$in_target_worktree" == true ]]; then
        message -m "Error: Cannot delete bare repository worktree" -c "$RED" -e 1
    fi
done < <(git worktree list --porcelain)

# Check if worktree was found
if [[ -z "$WORKTREE_PATH" ]]; then
    message -m "Error: Worktree '$WORKTREE_NAME' not found" -c "$RED" -n
    list_worktrees
    exit 1
fi

# Check if we found a branch
if [[ -z "$BRANCH_NAME" ]]; then
    message -m "Error: Could not determine branch name for worktree '$WORKTREE_NAME'" -c "$RED"
    message -m "This worktree may be in detached HEAD state" -c "$YELLOW" -e 1
fi

branch_tracking "$BRANCH_NAME"

# Safety check: prevent deleting main/master/develop branches without explicit confirmation
PROTECTED_BRANCHES=("main" "master" "develop" "development")
if [[ " ${PROTECTED_BRANCHES[*]} " =~ " $BRANCH_NAME " ]] && [[ "$FORCE" != true ]]; then
    message -m "⚠ WARNING: You are about to delete a protected branch: $BRANCH_NAME" -c "$YELLOW"
    message -m "This is typically not recommended!" -c "$YELLOW" -n
    read -p "Are you absolutely sure you want to delete '$BRANCH_NAME'? Type 'yes' to confirm: " -r
    if [[ "$REPLY" != "yes" ]]; then
        message -m "Operation cancelled for safety" -c "$YELLOW" -z
    fi
fi

# Check if we're currently in the worktree we want to delete
CURRENT_WORKTREE_PATH=$(git rev-parse --show-toplevel)
CURRENT_WORKTREE_NAME=$(basename "$CURRENT_WORKTREE_PATH")
IS_DELETING_CURRENT_WORKTREE=false

if [[ "$CURRENT_WORKTREE_NAME" == "$WORKTREE_NAME" ]]; then
    IS_DELETING_CURRENT_WORKTREE=true
    if [[ "$FORCE" != true ]]; then
        print_unpushed_warning
        message -m "⚠ You are currently in the worktree you want to delete ($WORKTREE_NAME)" -c "$YELLOW"
        message -m "You need to switch to a different worktree first." -c "$YELLOW" -n
        
        # Find another worktree to suggest
        list_worktrees "$WORKTREE_NAME"
        echo ""
        message -m "Please switch to another worktree and run this command again." -c "$YELLOW"
        message -m "Alternatively, you can use --force to delete from within the worktree (use at your own discretion)." -c "$YELLOW" -e 1
    fi
fi

# Show what will be deleted
message -m "Worktree name: $WORKTREE_NAME" -c "$YELLOW"
message -m "Worktree path: $WORKTREE_PATH" -c "$YELLOW"
message -m "Associated branch: $BRANCH_NAME" -c "$YELLOW"
message -m "Upstream: $TRACK_DISPLAY" -c "$YELLOW"

confirm_unpushed_commits

# Confirmation unless --force is used
if [[ "$FORCE" != true ]]; then
    echo ""
    read -p "Are you sure you want to delete this worktree and branch? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        message -m "Operation cancelled" -c "$YELLOW"
        message -m "Use --force to skip confirmation prompts." -c "$YELLOW" -z
    fi
fi

message -n -m "Proceeding with deletion..." -c "$YELLOW"

# If we're deleting the current worktree, find the main worktree path for git -C
if [[ "$IS_DELETING_CURRENT_WORKTREE" == true ]]; then
    # Get the main repository path using git rev-parse
    MAIN_WORKTREE_PATH=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    # Remove the .git suffix to get the worktree directory
    if [[ -n "$MAIN_WORKTREE_PATH" ]]; then
        MAIN_WORKTREE_PATH="${MAIN_WORKTREE_PATH%/.git}"
    fi
    
    if [[ -n "$MAIN_WORKTREE_PATH" ]] && [[ "$MAIN_WORKTREE_PATH" != "$WORKTREE_PATH" ]] && [[ -d "$MAIN_WORKTREE_PATH" ]]; then
        message -m "Using main worktree directory for operations..." -c "$YELLOW"
        # Move to the main worktree directory before any destructive operations
        cd "$MAIN_WORKTREE_PATH"
    else
        message -m "Warning: Could not determine main worktree path, proceeding from current location" -c "$YELLOW"
        MAIN_WORKTREE_PATH=""
    fi
fi

# Delete the local branch FIRST (before removing worktree)
message -m "Deleting local branch: $BRANCH_NAME" -c "$YELLOW"
BRANCH_DELETED=false
if [[ "$IS_DELETING_CURRENT_WORKTREE" == true ]] && [[ -n "$MAIN_WORKTREE_PATH" ]]; then
    if git -C "$MAIN_WORKTREE_PATH" branch -D "$BRANCH_NAME" 2> >(grep -v "error: Cannot delete branch" >&2); then
        message -m "✓ Local branch deleted successfully" -c "$GREEN"
        BRANCH_DELETED=true
    else
        message -m "⚠ Branch deletion failed (likely checked out), will be cleaned up after worktree removal" -c "$YELLOW"
    fi
else
    if git branch -D "$BRANCH_NAME" 2> >(grep -v "error: Cannot delete branch" >&2); then
        message -m "✓ Local branch deleted successfully" -c "$GREEN"
        BRANCH_DELETED=true
    else
        message -m "⚠ Branch deletion failed (likely checked out), will be cleaned up after worktree removal" -c "$YELLOW"
    fi
fi

# Remove worktree
message -m "Removing worktree at: $WORKTREE_PATH" -c "$YELLOW"
if [[ "$IS_DELETING_CURRENT_WORKTREE" == true ]] && [[ -n "$MAIN_WORKTREE_PATH" ]]; then
    if git -C "$MAIN_WORKTREE_PATH" worktree remove "$WORKTREE_PATH" --force; then
        message -m "✓ Worktree removed successfully" -c "$GREEN"
        # Move to main worktree path to avoid being in a deleted directory
        if [[ -n "$MAIN_WORKTREE_PATH" ]] && [[ -d "$MAIN_WORKTREE_PATH" ]]; then
            cd "$MAIN_WORKTREE_PATH"
        fi
    else
        message -m "✗ Failed to remove worktree" -c "$RED" -e 1
    fi
else
    if git worktree remove "$WORKTREE_PATH" --force; then
        message -m "✓ Worktree removed successfully" -c "$GREEN"
        # Move to main worktree path to avoid being in a deleted directory
        if [[ -n "$MAIN_WORKTREE_PATH" ]] && [[ -d "$MAIN_WORKTREE_PATH" ]]; then
            cd "$MAIN_WORKTREE_PATH"
        fi
    else
        message -m "✗ Failed to remove worktree" -c "$RED" -e 1
    fi
fi

# Try deleting the branch again if it failed the first time
if [[ "$BRANCH_DELETED" == false ]]; then
    message -m "Retrying branch deletion now that worktree is removed..." -c "$YELLOW"

    if [[ -n "$MAIN_WORKTREE_PATH" ]]; then
        GIT_CMD="$(which git) -C \"$MAIN_WORKTREE_PATH\" branch -D \"$BRANCH_NAME\""
    else
        GIT_CMD="$(which git) branch -D \"$BRANCH_NAME\""
    fi

    retry_count=0
    max_retries=3
    retry_delay=1
    output=""
    while [[ $retry_count -lt $max_retries ]] && [[ "$BRANCH_DELETED" == false ]] && [[ $output != *"not a git repository"* ]]; do
        if [[ $retry_count -gt 0 ]]; then
            message -m "Retry attempt $((retry_count + 1))/$max_retries..." -c "$YELLOW"
            sleep $retry_delay
        fi
        if output=$(bash -c "$GIT_CMD" 2>&1); then
            message -m "✓ Local branch deleted successfully after worktree removal" -c "$GREEN"
            BRANCH_DELETED=true
            break
        fi
        retry_count=$((retry_count + 1))
    done

    if [[ "$BRANCH_DELETED" == false ]]; then
        if [[ $output == *"not a git repository"* ]]; then
            message -m $'✗ Branch could not be deleted because the current working directory was deleted.\n  This is a limitation of Unix/POSIX systems: when your shell is left in a deleted directory, most commands (including git) will fail until you cd to a valid directory.\n  See: https://man7.org/linux/man-pages/man3/getcwd.3.html\n       https://stackoverflow.com/questions/4370798/what-happens-if-the-current-working-directory-is-deleted' -c "$RED"
        else
            message -m "✗ Branch could not be deleted after $max_retries attempts. It may still be checked out elsewhere or protected." -c "$RED"
        fi
        message -m "You can manually delete the branch using:" -c "$YELLOW"
        if [[ -n "$MAIN_WORKTREE_PATH" ]]; then
            message -m "  git -C \"$MAIN_WORKTREE_PATH\" branch -D \"$BRANCH_NAME\"" -c "$YELLOW"
        else
            message -m "  git branch -D \"$BRANCH_NAME\"" -c "$YELLOW"
        fi
    fi
fi

# Show the appropriate success message based on what was actually deleted
if [[ "$BRANCH_DELETED" == true ]]; then
    message -n -m "✓ Successfully deleted worktree '$WORKTREE_NAME' and branch '$BRANCH_NAME'" -c "$GREEN"
else
    message -n -m "✓ Successfully deleted worktree '$WORKTREE_NAME' (branch '$BRANCH_NAME' could not be deleted)" -c "$GREEN"
fi

