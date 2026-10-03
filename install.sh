#!/usr/bin/env bash
#
# Dotfiles installer & manager
# https://github.com/mimicryfull/dotfiles
#
# Automatically creates symbolic links from this repository to your system,
# so that any configuration edits made in your editors/apps immediately sync
# back to this git repository.

set -euo pipefail

# Determine script & repository directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$SCRIPT_DIR"

# Backup directory with timestamp
BACKUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${HOME}/.dotfiles_backup/${BACKUP_TIMESTAMP}"

# Color codes
COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_RED="\033[0;31m"
COLOR_GRAY="\033[0;90m"

DRY_RUN=false

log_info() {
  echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_ok() {
  echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
}

log_link() {
  echo -e "${COLOR_CYAN}[LINK]${COLOR_RESET} $*"
}

log_backup() {
  echo -e "${COLOR_YELLOW}[BACKUP]${COLOR_RESET} $*"
}

log_warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
}

log_err() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

get_real_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null || echo "$1"
  elif readlink -f "$1" >/dev/null 2>&1; then
    readlink -f "$1"
  else
    echo "$1"
  fi
}

is_linked_to() {
  local dest="$1"
  local src="$2"

  if [ -L "$dest" ]; then
    local target
    target="$(readlink "$dest" 2>/dev/null || true)"
    if [ "$target" = "$src" ]; then
      return 0
    fi
    local r_target r_src
    r_target="$(get_real_path "$dest")"
    r_src="$(get_real_path "$src")"
    if [ -n "$r_target" ] && [ "$r_target" = "$r_src" ]; then
      return 0
    fi
  fi
  return 1
}

backup_and_link() {
  local src="$1"
  local dest="$2"

  if [ ! -e "$src" ]; then
    log_warn "Source does not exist: $src (skipping)"
    return 0
  fi

  if is_linked_to "$dest" "$src"; then
    log_ok "Already linked: $dest -> $src"
    return 0
  fi

  if [ -L "$dest" ]; then
    # Destination is a symlink pointing somewhere else
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY-RUN] Would re-link symlink: $dest -> $src"
      return 0
    fi
    rm -f "$dest"
  elif [ -e "$dest" ]; then
    # Destination exists and is a regular file or directory
    if [ "$DRY_RUN" = true ]; then
      log_info "[DRY-RUN] Would backup $dest and link -> $src"
      return 0
    fi
    mkdir -p "$BACKUP_DIR"
    local rel_name
    rel_name="$(echo "$dest" | sed "s|^$HOME/||" | tr '/' '_')"
    local backup_target="${BACKUP_DIR}/${rel_name}"
    mv "$dest" "$backup_target"
    log_backup "Backed up existing $(basename "$dest") to $backup_target"
  fi

  if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would create link: $dest -> $src"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  log_link "$dest -> $src"
}

link_zed() {
  log_info "Configuring Zed..."
  if [ -d "$REPO_DIR/.config/zed" ]; then
    backup_and_link "$REPO_DIR/.config/zed" "$HOME/.config/zed"
  fi
  if [ -d "$REPO_DIR/.zed" ]; then
    backup_and_link "$REPO_DIR/.zed" "$HOME/.zed"
  fi
}

link_vscode() {
  local vscode_src="$REPO_DIR/.config/vscode"
  if [ ! -d "$vscode_src" ]; then
    return 0
  fi

  log_info "Configuring VS Code / Code - OSS..."

  local raw_user_dirs=()
  local raw_ext_dirs=()

  # 1. Code - OSS (Arch Linux / CachyOS)
  if [ -d "$HOME/.config/Code - OSS" ] || command -v code-oss >/dev/null 2>&1; then
    raw_user_dirs+=("$HOME/.config/Code - OSS/User")
    raw_ext_dirs+=("$HOME/.vscode-oss/extensions")
  fi

  # 2. Official Visual Studio Code (Linux)
  if [ -d "$HOME/.config/Code" ] || command -v code >/dev/null 2>&1; then
    raw_user_dirs+=("$HOME/.config/Code/User")
    raw_ext_dirs+=("$HOME/.vscode/extensions")
  fi

  # 3. VSCodium
  if [ -d "$HOME/.config/VSCodium" ] || command -v codium >/dev/null 2>&1; then
    raw_user_dirs+=("$HOME/.config/VSCodium/User")
    raw_ext_dirs+=("$HOME/.vscode-oss/extensions")
  fi

  # 4. macOS
  if [ -d "$HOME/Library/Application Support/Code" ]; then
    raw_user_dirs+=("$HOME/Library/Application Support/Code/User")
    raw_ext_dirs+=("$HOME/.vscode/extensions")
  fi

  # If none detected yet, link to standard Code and Code - OSS locations
  if [ ${#raw_user_dirs[@]} -eq 0 ]; then
    raw_user_dirs+=("$HOME/.config/Code - OSS/User" "$HOME/.config/Code/User")
    raw_ext_dirs+=("$HOME/.vscode-oss/extensions" "$HOME/.vscode/extensions")
  fi

  # Safely deduplicate preserving spaces in paths
  local unique_user_dirs=()
  while IFS= read -r line; do
    [ -n "$line" ] && unique_user_dirs+=("$line")
  done < <(printf "%s\n" "${raw_user_dirs[@]}" | sort -u)

  local unique_ext_dirs=()
  while IFS= read -r line; do
    [ -n "$line" ] && unique_ext_dirs+=("$line")
  done < <(printf "%s\n" "${raw_ext_dirs[@]}" | sort -u)

  # Link settings, keybindings, snippets into User directories
  for udir in "${unique_user_dirs[@]}"; do
    for f in "$vscode_src"/*; do
      [ -e "$f" ] || continue
      local bname="$(basename "$f")"
      if [ "$bname" = "extensions" ]; then
        continue
      fi
      backup_and_link "$f" "$udir/$bname"
    done
  done

  # Link extensions into extensions directories
  if [ -d "$vscode_src/extensions" ]; then
    for edir in "${unique_ext_dirs[@]}"; do
      for ext in "$vscode_src/extensions"/*; do
        [ -e "$ext" ] || continue
        backup_and_link "$ext" "$edir/$(basename "$ext")"
      done
    done
  fi
}

link_generic_config() {
  if [ -d "$REPO_DIR/.config" ]; then
    for item in "$REPO_DIR/.config"/*; do
      [ -e "$item" ] || continue
      local bname="$(basename "$item")"
      if [ "$bname" = "vscode" ] || [ "$bname" = "zed" ]; then
        continue
      fi
      log_info "Configuring .config/$bname..."
      backup_and_link "$item" "$HOME/.config/$bname"
    done
  fi
}

link_root_dotfiles() {
  for item in "$REPO_DIR"/.*; do
    [ -e "$item" ] || continue
    local bname="$(basename "$item")"
    case "$bname" in
      .|..|.git|.gitignore|.config|.zed|.gemini|.DS_Store)
        continue
        ;;
      *)
        log_info "Configuring $bname..."
        backup_and_link "$item" "$HOME/$bname"
        ;;
    esac
  done
}

install_all() {
  echo -e "${COLOR_BOLD}=== Installing Dotfiles ===${COLOR_RESET}"
  echo "Repository: $REPO_DIR"
  echo "Target:     $HOME"
  echo ""

  link_zed
  link_vscode
  link_generic_config
  link_root_dotfiles

  echo ""
  if [ -d "$BACKUP_DIR" ]; then
    log_backup "Previous configurations backed up to: $BACKUP_DIR"
  fi
  log_ok "${COLOR_BOLD}All dotfiles installed successfully!${COLOR_RESET}"
  echo -e "Any edits you make to these configs will immediately reflect in:"
  echo -e "  ${COLOR_CYAN}$REPO_DIR${COLOR_RESET}"
}

collect_links() {
  # Prints list of "dest|src" pairs
  [ -d "$REPO_DIR/.config/zed" ] && echo "$HOME/.config/zed|$REPO_DIR/.config/zed"
  [ -d "$REPO_DIR/.zed" ] && echo "$HOME/.zed|$REPO_DIR/.zed"

  if [ -d "$REPO_DIR/.config/vscode" ]; then
    for f in "$REPO_DIR/.config/vscode"/*; do
      [ -e "$f" ] || continue
      local bname="$(basename "$f")"
      [ "$bname" = "extensions" ] && continue
      [ -d "$HOME/.config/Code - OSS" ] && echo "$HOME/.config/Code - OSS/User/$bname|$f"
      [ -d "$HOME/.config/Code" ] && echo "$HOME/.config/Code/User/$bname|$f"
    done

    if [ -d "$REPO_DIR/.config/vscode/extensions" ]; then
      for ext in "$REPO_DIR/.config/vscode/extensions"/*; do
        [ -e "$ext" ] || continue
        local bname="$(basename "$ext")"
        [ -d "$HOME/.vscode-oss" ] && echo "$HOME/.vscode-oss/extensions/$bname|$ext"
        [ -d "$HOME/.vscode" ] && echo "$HOME/.vscode/extensions/$bname|$ext"
      done
    fi
  fi

  if [ -d "$REPO_DIR/.config" ]; then
    for item in "$REPO_DIR/.config"/*; do
      [ -e "$item" ] || continue
      local bname="$(basename "$item")"
      [ "$bname" = "vscode" ] || [ "$bname" = "zed" ] && continue
      echo "$HOME/.config/$bname|$item"
    done
  fi

  for item in "$REPO_DIR"/.*; do
    [ -e "$item" ] || continue
    local bname="$(basename "$item")"
    case "$bname" in
      .|..|.git|.gitignore|.config|.zed|.gemini|.DS_Store) continue ;;
      *) echo "$HOME/$bname|$item" ;;
    esac
  done
}

show_status() {
  echo -e "${COLOR_BOLD}=== Dotfiles Symlink Status ===${COLOR_RESET}"
  echo "Repository: $REPO_DIR"
  echo "Target:     $HOME"
  echo ""

  while IFS='|' read -r dest src; do
    [ -z "$dest" ] && continue
    if is_linked_to "$dest" "$src"; then
      echo -e "  ${COLOR_GREEN}✓ LINKED${COLOR_RESET}     $dest -> $src"
    elif [ -L "$dest" ]; then
      echo -e "  ${COLOR_YELLOW}⚠ WRONG LINK${COLOR_RESET} $dest -> $(readlink "$dest")"
    elif [ -e "$dest" ]; then
      echo -e "  ${COLOR_RED}✗ NOT LINKED${COLOR_RESET} $dest (regular file/dir, not symlink)"
    else
      echo -e "  ${COLOR_GRAY}- MISSING${COLOR_RESET}    $dest"
    fi
  done < <(collect_links)

  echo ""
  echo -e "${COLOR_BOLD}=== Git Working Tree Status ===${COLOR_RESET}"
  git -C "$REPO_DIR" status -s || true
  echo ""
}

unlink_all() {
  echo -e "${COLOR_BOLD}=== Unlinking Dotfiles ===${COLOR_RESET}"
  local count=0

  while IFS='|' read -r dest src; do
    [ -z "$dest" ] && continue
    if is_linked_to "$dest" "$src"; then
      rm "$dest"
      # If source was a directory, recreate empty directory or copy back
      if [ -d "$src" ]; then
        cp -a "$src" "$dest"
      else
        cp -a "$src" "$dest"
      fi
      log_ok "Restored regular file/dir: $dest (unlinked from repo)"
      count=$((count + 1))
    fi
  done < <(collect_links)

  if [ "$count" -eq 0 ]; then
    log_info "No active dotfiles symlinks found."
  else
    log_ok "Unlinked $count target(s). Files were copied back into your system."
  fi
}

add_to_dotfiles() {
  local input_path="${1:-}"
  if [ -z "$input_path" ]; then
    log_err "Please provide the file or directory path to add."
    echo "Usage: $0 add <path>"
    echo "Example: $0 add ~/.config/kitty"
    echo "Example: $0 add ~/.zshrc"
    exit 1
  fi

  # Expand ~ if needed
  local resolved_path="${input_path/#\~/$HOME}"
  if [ ! -e "$resolved_path" ] && [ ! -L "$resolved_path" ]; then
    log_err "Path not found: $input_path"
    exit 1
  fi

  local real_target
  real_target="$(get_real_path "$resolved_path")"
  case "$real_target" in
    "$REPO_DIR"*)
      log_ok "$input_path is already inside the dotfiles repository!"
      return 0
      ;;
  esac

  local repo_dest=""
  if [[ "$resolved_path" == "$HOME/.config/"* ]]; then
    local rel="${resolved_path#$HOME/.config/}"
    repo_dest="$REPO_DIR/.config/$rel"
  elif [[ "$resolved_path" == "$HOME/"* ]]; then
    local rel="${resolved_path#$HOME/}"
    repo_dest="$REPO_DIR/$rel"
  else
    log_err "Path must be inside your home directory ($HOME): $resolved_path"
    exit 1
  fi

  log_info "Adopting $resolved_path into dotfiles repository at $repo_dest..."
  mkdir -p "$(dirname "$repo_dest")"

  if [ -e "$repo_dest" ]; then
    log_warn "$repo_dest already exists in repository. Merging/overwriting..."
  fi

  mv "$resolved_path" "$repo_dest"
  backup_and_link "$repo_dest" "$resolved_path"

  echo ""
  log_ok "Successfully added and symlinked $resolved_path!"
  echo -e "To commit your new configuration:"
  echo -e "  ${COLOR_CYAN}cd \"$REPO_DIR\" && git add . && git commit -m \"Add $(basename "$repo_dest")\"${COLOR_RESET}"
}

sync_dotfiles() {
  local commit_msg="${1:-Update dotfiles: $(date '+%Y-%m-%d %H:%M')}"
  log_info "Staging all changes in $REPO_DIR..."
  git -C "$REPO_DIR" add -A

  if git -C "$REPO_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
    log_ok "Working tree clean, nothing new to commit."
  else
    git -C "$REPO_DIR" commit -m "$commit_msg"
    log_ok "Committed: $commit_msg"
  fi

  log_info "Pushing to remote repository..."
  git -C "$REPO_DIR" push
  log_ok "All changes successfully pushed!"
}

show_help() {
  echo -e "${COLOR_BOLD}Dotfiles Manager${COLOR_RESET}"
  echo ""
  echo "Usage:"
  echo "  $0                  Install / create all symlinks"
  echo "  $0 status           Check current link status and git status"
  echo "  $0 add <path>       Adopt an existing config into dotfiles and symlink it"
  echo "  $0 sync [message]   Stage all changes, commit, and push to GitHub"
  echo "  $0 unlink           Remove symlinks and restore local copies"
  echo "  $0 --dry-run        Preview actions without making changes"
  echo "  $0 --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 add ~/.config/kitty"
  echo "  $0 sync \"Update Zed keybindings\""
}

main() {
  local command="${1:-}"

  case "$command" in
    -h|--help|help)
      show_help
      ;;
    -n|--dry-run)
      DRY_RUN=true
      install_all
      ;;
    status|--status)
      show_status
      ;;
    unlink|--unlink)
      unlink_all
      ;;
    add)
      shift
      add_to_dotfiles "${1:-}"
      ;;
    sync)
      shift
      sync_dotfiles "${1:-}"
      ;;
    "")
      install_all
      ;;
    *)
      log_err "Unknown command: $command"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

main "$@"
