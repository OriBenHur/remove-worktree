# remove-worktree

A Git alias script that safely deletes both a worktree folder and its associated local branch in one command. This script provides a convenient way to clean up completed feature branches and their worktrees.

## Features

- 🗑️ **Complete cleanup**: Removes both the worktree directory and its associated local branch
- 🛡️ **Safety checks**: Prevents accidental deletion of protected branches (main, master, develop), checks that the upstream branch still exists on the remote, and asks again when deleting would drop commits that are not there
- 📋 **Smart detection**: Automatically detects the current worktree if no name is provided
- 🔍 **Worktree listing**: List all available worktrees with their branches and paths
- ⚠️ **Confirmation prompts**: Interactive confirmation to prevent accidental deletions
- 🎨 **Colored output**: Clear visual feedback with color-coded messages
- 🚫 **Force option**: Skip confirmations with `--force` flag
- 🔄 **Current worktree support**: Can delete the worktree you're currently in (with `--force`)
- 🧹 **Automatic cleanup**: Handles branch deletion even when checked out in current worktree
- 💡 **Helpful hints**: Provides guidance on using `--force` when appropriate

## Installation

### Option 1: Direct Installation

1. Download the script:
```bash
curl -o git-delete-worktree https://raw.githubusercontent.com/yourusername/remove-worktree/main/remove-worktree.sh
```

2. Make it executable:
```bash
chmod +x git-delete-worktree
```

3. Move to a directory in your PATH:
```bash
sudo mv git-delete-worktree /usr/local/bin/
```

### Option 2: Git Alias Setup

1. Copy the script to your preferred location:
```bash
cp remove-worktree.sh ~/bin/git-delete-worktree
chmod +x ~/bin/git-delete-worktree
```

2. Add to your PATH (if not already added):
```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
# or for zsh:
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

3. Create a Git alias:
```bash
git config --global alias.delete-worktree '!git-delete-worktree'
```

## Usage

### Basic Commands

```bash
# Delete the current worktree and its branch
git delete-worktree

# Delete a specific worktree by name
git delete-worktree feature-branch

# Delete without confirmation prompts
git delete-worktree feature-branch --force

# List all available worktrees
git delete-worktree --list
```

### Command Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-f, --force` | Force deletion without confirmation |
| `-l, --list` | List all available worktrees |

### Examples

```bash
# Delete current worktree (if you're inside it, you'll be prompted to switch first)
git delete-worktree

# Delete current worktree with force (bypasses current worktree protection)
git delete-worktree --force

# Delete a specific feature branch worktree
git delete-worktree my-feature-branch

# Delete a worktree without any prompts
git delete-worktree temp-branch -f

# See what worktrees are available
git delete-worktree -l
```

## How It Works

1. **Worktree Detection**: The script finds the worktree by name (folder name, not full path)
2. **Branch Association**: Automatically determines the local branch associated with the worktree
3. **Safety Checks**: 
   - Prevents deletion of protected branches (main, master, develop) without explicit confirmation
   - Asks the remote whether the upstream branch still exists, without fetching
   - Asks for an extra confirmation when that branch is missing or unreachable, or the local branch is ahead of it
   - Validates that the worktree exists
4. **Smart Deletion Process**:
   - Attempts to delete the branch first (if possible)
   - Removes the worktree using `git worktree remove`
   - Handles current worktree deletion gracefully using main worktree as base
   - Automatically changes directory to avoid issues with deleted directories

## Safety Features

### Protected Branches
The script protects important branches by default:
- `main`
- `master` 
- `develop`
- `development`

To delete these branches, you must either:
- Use the `--force` flag, or
- Explicitly type "yes" when prompted

### Upstream and unpushed commits
The script reads the branch's configured upstream, then asks that remote whether the branch is still there (`git ls-remote --heads`). A remote-tracking ref left in the local repository is not treated as proof. The script does not fetch and does not update remote-tracking refs.

Before deleting, it prints that upstream:

- `origin/feature` when the branch is on the remote and the local branch matches that commit
- `origin/feature (ahead 2)` when the local branch has commits the remote branch does not
- `origin/feature (behind 1)` or `origin/feature (ahead 2, behind 1)` when the histories differ that way
- `origin/feature (not on origin)` when the remote does not have that branch
- `origin/feature (on origin; tip not fetched)` when the remote has the branch but that commit is not in this repository
- `origin/feature (could not check origin)` when the remote could not be contacted
- `none` when no upstream is configured

Deletion stops for an extra confirmation (type `yes`) when:

- the branch is ahead of the commit currently on the remote, or
- the remote no longer has the branch and the local branch has commits that are not on any remote, or
- the remote has the branch but its commit is not available locally, or
- the remote could not be contacted, or
- there is no upstream and the branch has commits that are not on any remote

`--force` skips the prompt. The upstream line is still printed. Those commits remain in the reflog until it expires. The remote branch is left in place.

### Current Worktree Protection
If you're currently inside the worktree you want to delete, the script will:
1. Show you a list of other available worktrees
2. Prompt you to switch to a different worktree first
3. Provide a hint about using `--force` to delete from within the worktree
4. Exit safely without making any changes

**Note**: The `--force` flag bypasses this protection, allowing you to delete the current worktree safely.

### Confirmation Prompts
By default, the script asks for confirmation before deletion:
- Shows the worktree name, path, and associated branch
- Requires explicit confirmation (y/N)
- Can be bypassed with `--force` flag
- Provides helpful hints about using `--force` when cancelled

## Advanced Features

### Current Worktree Deletion
The script can safely delete the worktree you're currently in when using `--force`:
- Automatically detects when you're in the target worktree
- Uses the main worktree as the base for git operations
- Handles branch deletion gracefully (even if checked out)
- Automatically changes directory to avoid shell issues
- Provides clear feedback about the process

### Intelligent Branch Cleanup
- Attempts to delete the branch before removing the worktree
- Handles cases where the branch is currently checked out
- Provides informative messages about cleanup status
- Suppresses unnecessary error messages for better UX

## Output Examples

### Listing Worktrees
```bash
$ git delete-worktree --list
Available worktrees:
  NAME              BRANCH           UPSTREAM                         PATH
  ----------------  ----------------  -------------------------------  --------------------------------------------------
  main              main              origin/main                      /path/to/repo
  feature-login     feature/login     origin/feature/login (ahead 1)   /path/to/repo/feature-login
  bugfix-123        bugfix/issue-123  none (2 not on any remote)       /path/to/repo/bugfix-123
```

### Deleting a Worktree
```bash
$ git delete-worktree feature-login
Worktree name: feature-login
Worktree path: /path/to/repo/feature-login
Associated branch: feature/login
Upstream: origin/feature/login

Are you sure you want to delete this worktree and branch? (y/N): y

Proceeding with deletion...
Deleting local branch: feature/login
✓ Local branch deleted successfully
Removing worktree at: /path/to/repo/feature-login
✓ Worktree removed successfully

✓ Successfully deleted worktree 'feature-login' and branch 'feature/login'
```

### Deleting Current Worktree with Force
```bash
$ git delete-worktree --force
Worktree name: feature-login
Worktree path: /path/to/repo/feature-login
Associated branch: feature/login
Upstream: origin/feature/login (ahead 1)

Proceeding with deletion...
Using main worktree directory for operations...
Deleting local branch: feature/login
⚠ Branch deletion failed (likely checked out), will be cleaned up after worktree removal
Removing worktree at: /path/to/repo/feature-login
✓ Worktree removed successfully

✓ Successfully deleted worktree 'feature-login' and branch 'feature-login'
```

## ⚠️ Note on Deleting Worktrees from Within Themselves

When you run this script from inside a worktree and that worktree is deleted, your shell is left in a deleted directory. This is a limitation of Unix/POSIX systems:

- Most commands (including git) will fail until you `cd` to a valid directory.
- The script will print a warning and suggest a `cd` command to recover.
- This is not a bug in the script, but a fundamental behavior of Unix shells and filesystems.

**References:**
- [getcwd(3) man page](https://man7.org/linux/man-pages/man3/getcwd.3.html)
- [Stack Overflow: What happens if the current working directory is deleted?](https://unix.stackexchange.com/questions/434417/what-happens-when-the-current-directory-is-deleted)

**Example error message:**
```
✗ Branch could not be deleted because the current working directory was deleted.
  This is a limitation of Unix/POSIX systems: when your shell is left in a deleted directory, most commands (including git) will fail until you cd to a valid directory.
  See: https://man7.org/linux/man-pages/man3/getcwd.3.html
       https://stackoverflow.com/questions/4370798/what-happens-if-the-current-working-directory-is-deleted
```

## Requirements

- Git 2.5+ (for worktree support)
- Bash shell
- Unix-like operating system (Linux, macOS, WSL)

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Not in a Git repository" | Make sure you're running the command from within a Git repository |
| "Worktree not found" | Check the worktree name (use `--list` to see available worktrees). Worktree names are folder names, not full paths |
| "Cannot delete bare repository worktree" | The script cannot delete bare repository worktrees. This is a Git limitation |
| Permission Denied | Make sure the script is executable: `chmod +x git-delete-worktree` |
| Branch deletion fails | This is normal when deleting the current worktree. The branch will be cleaned up automatically after the worktree is removed |

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [MIT License](LICENSE.md).

## Related

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [Git Branch Documentation](https://git-scm.com/docs/git-branch)
