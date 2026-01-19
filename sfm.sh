#!/bin/bash
set -euo pipefail

# ---------------------------
# Colors (auto-disable if not tty / NO_COLOR)
# ---------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; MAGENTA=""; NC=""; BOLD=""
fi

# ---------------------------
# Configuration
# ---------------------------
SFM_DIR="$HOME/.sfm"
FUNCTIONS_FILE_BASE="$SFM_DIR/functions"
ALIASES_FILE_BASE="$SFM_DIR/aliases"
LOG_FILE="$SFM_DIR/setup.log"

BATCH_MODE=false
YES_TO_ALL=false

# If set by --shell, it overrides $SHELL detection
TARGET_SHELL_OVERRIDE=""

SHELL_NAME=""
SHELL_CONFIG=""
FUNCTIONS_FILE=""
ALIASES_FILE=""

PKG_MANAGER=""
PKG_INSTALL_CMD=""
DISTRO_NAME=""

SFM_BEGIN="# >>> SFM >>>"
SFM_END="# <<< SFM <<<"

# ---------------------------
# Logging
# ---------------------------
ensure_log_ready() {
  mkdir -p "$SFM_DIR"
  touch "$LOG_FILE"
}

log() {
  local level="${2:-INFO}"
  local msg="$1"
  ensure_log_ready
  printf '[%s] [%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE"
}

log_error() { log "$1" "ERROR"; printf '%b\n' "${RED}ERROR:${NC} $1" >&2; }
log_warn()  { log "$1" "WARN";  printf '%b\n' "${YELLOW}WARNING:${NC} $1"; }
log_info()  { log "$1" "INFO"; }

# ---------------------------
# UX helpers
# ---------------------------
spinner() {
  local pid="$1"
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while ps -p "$pid" >/dev/null 2>&1; do
    local temp="${spinstr#?}"
    printf " [%s]  " "${spinstr%"$temp"}"
    spinstr="$temp${spinstr%"$temp"}"
    sleep "$delay"
    printf "\b\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

ask_yn() {
  local prompt="$1"

  if [[ "$YES_TO_ALL" == true ]]; then
    return 0
  fi

  local response=""
  while true; do
    printf "%b" "${CYAN}${prompt}${NC} [y/n]: "
    IFS= read -r response
    case "$response" in
      [Yy]* ) return 0 ;;
      [Nn]* ) return 1 ;;
      * ) printf '%b\n' "${RED}Please answer y or n${NC}" ;;
    esac
  done
}

show_help() {
  cat <<EOF
${BOLD}SFM (Shell Function Manager) Setup${NC}

${BOLD}Usage:${NC} $0 [OPTIONS]

${BOLD}Options:${NC}
  -b, --batch              Batch mode (assume yes)
  -y, --yes                Answer yes to prompts
  -h, --help               Show this help
  --uninstall, --rollback  Remove SFM config + optionally delete ~/.sfm
  --shell <bash|zsh|fish>  Force target shell (otherwise uses \$SHELL)

${BOLD}What is SFM?${NC}
Installs useful shell functions + aliases:
  • extract, mkcd, psgrep, backup, myip, portcheck
EOF
}

error_handler() {
  local line_no="$1"
  printf '%b\n' "${RED}Error on line $line_no${NC}" >&2
  printf '%b\n' "${YELLOW}Check $LOG_FILE for details${NC}" >&2
  log "Script failed at line $line_no" "ERROR"

  # If stdin isn't interactive, don't prompt
  if [[ -t 0 ]]; then
    if ask_yn "View last 20 lines of the log?"; then
      tail -20 "$LOG_FILE" || true
    fi
  fi
  exit 1
}

trap 'error_handler ${LINENO}' ERR

# ---------------------------
# Atomic file write
# ---------------------------
atomic_write() {
  local target="$1"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  chmod 0644 "$tmp"
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
}

# ---------------------------
# Detect distro
# ---------------------------
detect_distro() {
  log "Detecting distribution..."
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_NAME="${NAME:-Unknown}"
    printf '%b\n\n' "${GREEN}✓${NC} Distribution: ${BOLD}${DISTRO_NAME}${NC}"
    log "Distribution: $DISTRO_NAME"
  else
    DISTRO_NAME="Unknown"
    printf '%b\n\n' "${YELLOW}⚠${NC} Could not detect distribution"
    log "Could not detect distribution" "WARN"
  fi
}

# ---------------------------
# Detect package manager
# - system managers for dependencies
# - universal managers only informational
# ---------------------------
detect_package_manager() {
  log "Detecting package manager..."

  local system_managers=()
  local universal_managers=()

  command -v apt    >/dev/null 2>&1 && system_managers+=("apt")
  command -v dnf    >/dev/null 2>&1 && system_managers+=("dnf")
  command -v yum    >/dev/null 2>&1 && system_managers+=("yum")
  command -v yay    >/dev/null 2>&1 && system_managers+=("yay")
  command -v pacman >/dev/null 2>&1 && system_managers+=("pacman")
  command -v zypper >/dev/null 2>&1 && system_managers+=("zypper")
  command -v apk    >/dev/null 2>&1 && system_managers+=("apk")

  command -v flatpak >/dev/null 2>&1 && universal_managers+=("flatpak")
  command -v snap    >/dev/null 2>&1 && universal_managers+=("snap")

  PKG_MANAGER="none"
  PKG_INSTALL_CMD=""

  # Pick a primary SYSTEM package manager by priority
  for mgr in apt dnf yum yay pacman zypper apk; do
    if [[ " ${system_managers[*]} " == *" $mgr "* ]]; then
      PKG_MANAGER="$mgr"
      break
    fi
  done

  case "$PKG_MANAGER" in
    apt)    PKG_INSTALL_CMD="sudo apt-get install -y" ;;
    dnf)    PKG_INSTALL_CMD="sudo dnf install -y" ;;
    yum)    PKG_INSTALL_CMD="sudo yum install -y" ;;
    yay)    PKG_INSTALL_CMD="yay -S --noconfirm --needed" ;;
    pacman) PKG_INSTALL_CMD="sudo pacman -S --noconfirm --needed" ;;
    zypper) PKG_INSTALL_CMD="sudo zypper install -y" ;;
    apk)    PKG_INSTALL_CMD="sudo apk add" ;;
    none)   ;;
  esac

  if [[ "$PKG_MANAGER" == "none" ]]; then
    printf '%b\n' "${YELLOW}⚠${NC} No system package manager detected (deps cannot be auto-installed)"
    log "No system package manager detected" "WARN"
  else
    printf '%b\n' "${GREEN}✓${NC} Package manager: ${BOLD}${PKG_MANAGER}${NC}"
    log "Primary package manager: $PKG_MANAGER"
  fi

  local all_managers=("${system_managers[@]}" "${universal_managers[@]}")
  if (( ${#all_managers[@]} > 0 )); then
    local extras=()
    for m in "${all_managers[@]}"; do
      [[ "$m" != "$PKG_MANAGER" ]] && extras+=("$m")
    done
    if (( ${#extras[@]} > 0 )); then
      printf '%b\n' "${BLUE}ℹ${NC} Also detected: ${extras[*]}"
      log "Additional package managers: ${extras[*]}"
    fi
  fi

  printf '\n'
  return 0
}

# ---------------------------
# Detect shell (IMPORTANT FIX: use $SHELL, not BASH_VERSION)
# ---------------------------
detect_shell() {
  log "Detecting target shell..."

  local shell_guess=""
  if [[ -n "$TARGET_SHELL_OVERRIDE" ]]; then
    shell_guess="$TARGET_SHELL_OVERRIDE"
  else
    shell_guess="$(basename "${SHELL:-bash}")"
  fi

  case "$shell_guess" in
    bash|zsh|fish) ;;
    *)
      log_warn "Unsupported/unknown \$SHELL='$shell_guess' -> defaulting to bash"
      shell_guess="bash"
      ;;
  esac

  SHELL_NAME="$shell_guess"

  case "$SHELL_NAME" in
    bash)
      SHELL_CONFIG="$HOME/.bashrc"
      [[ -f "$HOME/.bash_profile" ]] && SHELL_CONFIG="$HOME/.bash_profile"
      FUNCTIONS_FILE="${FUNCTIONS_FILE_BASE}.sh"
      ALIASES_FILE="${ALIASES_FILE_BASE}.sh"
      ;;
    zsh)
      SHELL_CONFIG="$HOME/.zshrc"
      FUNCTIONS_FILE="${FUNCTIONS_FILE_BASE}.sh"
      ALIASES_FILE="${ALIASES_FILE_BASE}.sh"
      ;;
    fish)
      # We'll use conf.d (smooth + no editing config.fish needed)
      SHELL_CONFIG="$HOME/.config/fish/conf.d/sfm.fish"
      FUNCTIONS_FILE="${FUNCTIONS_FILE_BASE}.fish"
      ALIASES_FILE="${ALIASES_FILE_BASE}.fish"
      mkdir -p "$HOME/.config/fish/conf.d"
      ;;
  esac

  printf '%b\n' "${GREEN}✓${NC} Shell: ${BOLD}${SHELL_NAME}${NC}"
  printf '%b\n\n' "${GREEN}✓${NC} Config target: ${BOLD}${SHELL_CONFIG}${NC}"
  log "Shell: $SHELL_NAME, Config: $SHELL_CONFIG"
}

# ---------------------------
# Dependencies
# ---------------------------
install_missing_deps() {
  local missing=("$@")

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  if [[ "$PKG_MANAGER" == "none" ]]; then
    printf '%b\n' "${YELLOW}Please install manually:${NC} ${missing[*]}"
    log_warn "Manual install required: ${missing[*]}"
    return 0
  fi

  if ! ask_yn "Install missing dependencies (${missing[*]})?"; then
    log_warn "User skipped installing deps: ${missing[*]}"
    return 0
  fi

  printf '%b\n' "${CYAN}Installing: ${missing[*]}...${NC}"
  log_info "Installing deps: ${missing[*]}"

  if [[ "$BATCH_MODE" == false ]]; then
    # run with spinner
    # shellcheck disable=SC2086
    $PKG_INSTALL_CMD "${missing[@]}" >>"$LOG_FILE" 2>&1 &
    local pid=$!
    spinner "$pid"
    if wait "$pid"; then
      printf '%b\n' "${GREEN}✓${NC} Dependencies installed"
      log_info "Deps installed successfully"
    else
      printf '%b\n' "${RED}✗${NC} Dependency install failed. See $LOG_FILE"
      log_error "Failed installing deps"
    fi
  else
    # shellcheck disable=SC2086
    if $PKG_INSTALL_CMD "${missing[@]}" >>"$LOG_FILE" 2>&1; then
      printf '%b\n' "${GREEN}✓${NC} Dependencies installed"
      log_info "Deps installed successfully"
    else
      printf '%b\n' "${RED}✗${NC} Dependency install failed. See $LOG_FILE"
      log_error "Failed installing deps"
    fi
  fi
}

check_dependencies() {
  printf '%b\n' "${BOLD}Checking dependencies...${NC}"
  log "Checking dependencies..."

  local missing=()

  # Required tools for core workflow
  for dep in tar gzip bzip2 unzip; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
      printf '%b\n' "${YELLOW}⚠${NC} Missing: $dep"
    else
      printf '%b\n' "${GREEN}✓${NC} Found: $dep"
    fi
  done

  # curl OR wget is enough
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=("curl")
    printf '%b\n' "${YELLOW}⚠${NC} Missing: curl (or wget)"
  else
    command -v curl >/dev/null 2>&1 && printf '%b\n' "${GREEN}✓${NC} Found: curl"
    command -v wget >/dev/null 2>&1 && printf '%b\n' "${GREEN}✓${NC} Found: wget"
  fi

  printf '\n'
  install_missing_deps "${missing[@]}"
  printf '\n'
}

# ---------------------------
# Validate generated file
# ---------------------------
validate_functions_file() {
  local file="$1"

  if [[ "$SHELL_NAME" == "bash" || "$SHELL_NAME" == "zsh" ]]; then
    if bash -n "$file" >/dev/null 2>&1; then
      printf '%b\n' "${GREEN}✓${NC} Syntax check passed"
      log_info "Syntax validation passed for $file"
      return 0
    else
      printf '%b\n' "${RED}✗${NC} Syntax errors detected in $file"
      log_error "Syntax validation failed for $file"
      return 1
    fi
  fi
  return 0
}

# ---------------------------
# Generate functions + aliases
# ---------------------------
generate_functions() {
  printf '%b\n' "${BOLD}Generating shell functions...${NC}"
  log "Generating functions file: $FUNCTIONS_FILE"

  if [[ "$SHELL_NAME" == "fish" ]]; then
    atomic_write "$FUNCTIONS_FILE" <<'EOF'
function extract
    if test (count $argv) -eq 0
        echo "Usage: extract <file>"
        return 1
    end

    if not test -f $argv[1]
        echo "Error: '$argv[1]' is not a valid file"
        return 1
    end

    switch $argv[1]
        case '*.tar.bz2'
            tar xjf $argv[1]
        case '*.tar.gz'
            tar xzf $argv[1]
        case '*.bz2'
            bunzip2 $argv[1]
        case '*.rar'
            unrar x $argv[1]
        case '*.gz'
            gunzip $argv[1]
        case '*.tar'
            tar xf $argv[1]
        case '*.tbz2'
            tar xjf $argv[1]
        case '*.tgz'
            tar xzf $argv[1]
        case '*.zip'
            unzip $argv[1]
        case '*.Z'
            uncompress $argv[1]
        case '*.7z'
            7z x $argv[1]
        case '*.tar.xz'
            tar xf $argv[1]
        case '*'
            echo "Error: '$argv[1]' cannot be extracted via extract()"
            return 1
    end
end

function mkcd
    if test (count $argv) -eq 0
        echo "Usage: mkcd <dir>"
        return 1
    end
    mkdir -p $argv[1]; and cd $argv[1]
end

function psgrep
    if test (count $argv) -eq 0
        echo "Usage: psgrep <pattern>"
        return 1
    end
    ps aux | grep -v grep | grep -i -e VSZ -e $argv[1]
end

function backup
    if test (count $argv) -eq 0
        echo "Usage: backup <file_or_directory>"
        return 1
    end

    set target $argv[1]
    set timestamp (date +%Y%m%d_%H%M%S)
    cp -r "$target" "$target.backup_$timestamp"
    echo "Backup created: $target.backup_$timestamp"
end

function myip
    echo "Local IP:"
    hostname -I 2>/dev/null; or ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1
    echo ""
    echo "Public IP:"
    if command -v curl >/dev/null
        curl -s ifconfig.me
    else if command -v wget >/dev/null
        wget -qO- ifconfig.me
    else
        echo "curl or wget required"
    end
    echo ""
end

function portcheck
    if test (count $argv) -eq 0
        echo "Usage: portcheck <port>"
        return 1
    end

    if command -v lsof >/dev/null
        sudo lsof -i :$argv[1]
    else if command -v ss >/dev/null
        ss -tulpn | grep :$argv[1]
    else
        echo "lsof or ss required"
        return 1
    end
end
EOF
  else
    atomic_write "$FUNCTIONS_FILE" <<'EOF'
extract() {
    if [ -z "${1:-}" ]; then
        echo "Usage: extract <file>"
        return 1
    fi

    if [ ! -f "$1" ]; then
        echo "Error: '$1' is not a valid file"
        return 1
    fi

    case "$1" in
        *.tar.bz2)   tar xjf "$1"    ;;
        *.tar.gz)    tar xzf "$1"    ;;
        *.bz2)       bunzip2 "$1"    ;;
        *.rar)       unrar x "$1"    ;;
        *.gz)        gunzip "$1"     ;;
        *.tar)       tar xf "$1"     ;;
        *.tbz2)      tar xjf "$1"    ;;
        *.tgz)       tar xzf "$1"    ;;
        *.zip)       unzip "$1"      ;;
        *.Z)         uncompress "$1" ;;
        *.7z)        7z x "$1"       ;;
        *.tar.xz)    tar xf "$1"     ;;
        *)           echo "Error: '$1' cannot be extracted via extract()" ; return 1 ;;
    esac
}

mkcd() {
    if [ -z "${1:-}" ]; then
        echo "Usage: mkcd <dir>"
        return 1
    fi
    mkdir -p "$1" && cd "$1"
}

psgrep() {
    if [ $# -eq 0 ]; then
        echo "Usage: psgrep <pattern>"
        return 1
    fi
    ps aux | grep -v grep | grep -i -e VSZ -e "$@"
}

backup() {
    if [ -z "${1:-}" ]; then
        echo "Usage: backup <file_or_directory>"
        return 1
    fi

    local target="$1"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    cp -r "$target" "$target.backup_$timestamp"
    echo "Backup created: $target.backup_$timestamp"
}

myip() {
    echo "Local IP:"
    hostname -I 2>/dev/null || ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1
    echo ""
    echo "Public IP:"
    if command -v curl >/dev/null 2>&1; then
        curl -s ifconfig.me
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- ifconfig.me
    else
        echo "curl or wget required"
    fi
    echo ""
}

portcheck() {
    if [ -z "${1:-}" ]; then
        echo "Usage: portcheck <port>"
        return 1
    fi

    if command -v lsof >/dev/null 2>&1; then
        sudo lsof -i :"$1"
    elif command -v ss >/dev/null 2>&1; then
        ss -tulpn | grep ":$1"
    else
        echo "lsof or ss required"
        return 1
    fi
}
EOF
  fi

  printf '%b\n' "${GREEN}✓${NC} Functions file created: $FUNCTIONS_FILE"
  validate_functions_file "$FUNCTIONS_FILE"
  log "Generated functions file: $FUNCTIONS_FILE"
  printf '\n'
}

generate_aliases() {
  printf '%b\n' "${BOLD}Generating shell aliases...${NC}"
  log "Generating aliases file: $ALIASES_FILE"

  if [[ "$SHELL_NAME" == "fish" ]]; then
    atomic_write "$ALIASES_FILE" <<'EOF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias ll='ls -lh'
alias la='ls -lAh'
alias l='ls -CF'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias c='clear'
alias h='history'

if command -v ss >/dev/null
    alias ports='ss -tulpen'
else if command -v netstat >/dev/null
    alias ports='netstat -tulanp'
end

if command -v free >/dev/null
    alias meminfo='free -m -l -t'
end

alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

if command -v git >/dev/null
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph --decorate'
end
EOF
  else
    atomic_write "$ALIASES_FILE" <<'EOF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias ll='ls -lh'
alias la='ls -lAh'
alias l='ls -CF'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias c='clear'
alias h='history'

if command -v ss >/dev/null 2>&1; then
  alias ports='ss -tulpen'
elif command -v netstat >/dev/null 2>&1; then
  alias ports='netstat -tulanp'
fi

if command -v free >/dev/null 2>&1; then
  alias meminfo='free -m -l -t'
fi

alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'

if command -v git >/dev/null 2>&1; then
  alias gs='git status'
  alias ga='git add'
  alias gc='git commit'
  alias gp='git push'
  alias gl='git log --oneline --graph --decorate'
fi
EOF
  fi

  printf '%b\n' "${GREEN}✓${NC} Aliases file created: $ALIASES_FILE"
  log "Generated aliases file: $ALIASES_FILE"
  printf '\n'
}

# ---------------------------
# Config wiring (idempotent)
# - fish: write conf.d/sfm.fish (best practice)
# - bash/zsh: add a marked block to rc
# ---------------------------
update_shell_config() {
  printf '%b\n\n' "${BOLD}Updating shell configuration...${NC}"

  if [[ "$SHELL_NAME" == "fish" ]]; then
    # fish loads conf.d automatically
    atomic_write "$SHELL_CONFIG" <<EOF
# SFM - Shell Function Manager (auto-loaded by fish)
test -f "$FUNCTIONS_FILE"; and source "$FUNCTIONS_FILE"
test -f "$ALIASES_FILE"; and source "$ALIASES_FILE"
EOF
    printf '%b\n\n' "${GREEN}✓${NC} Fish drop-in created: ${BOLD}$SHELL_CONFIG${NC}"
    log_info "Fish drop-in created: $SHELL_CONFIG"
    return 0
  fi

  if ! ask_yn "Automatically source SFM in your $SHELL_CONFIG?"; then
    printf '%b\n' "${YELLOW}Skipped auto-config.${NC}"
    printf '%b\n' "Add this block manually to ${BOLD}$SHELL_CONFIG${NC}:"
    printf '\n'
    cat <<EOF
$SFM_BEGIN
[ -f "$FUNCTIONS_FILE" ] && source "$FUNCTIONS_FILE"
[ -f "$ALIASES_FILE" ] && source "$ALIASES_FILE"
$SFM_END
EOF
    printf '\n'
    return 0
  fi

  touch "$SHELL_CONFIG"

  local backup_file="${SHELL_CONFIG}.sfm-backup-$(date +%Y%m%d_%H%M%S)"
  cp "$SHELL_CONFIG" "$backup_file"
  printf '%b\n' "${GREEN}✓${NC} Backed up to: ${backup_file##*/}"
  log_info "Backed up shell config to: $backup_file"

  # Remove old block (if any)
  if grep -qF "$SFM_BEGIN" "$SHELL_CONFIG" 2>/dev/null; then
    log_info "Removing old SFM block from $SHELL_CONFIG"
    # delete from begin marker to end marker inclusive
    sed -i.bak "/$(printf '%s' "$SFM_BEGIN" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/,/$(printf '%s' "$SFM_END" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/d" "$SHELL_CONFIG" || true
    rm -f "${SHELL_CONFIG}.bak" || true
  fi

  cat >>"$SHELL_CONFIG" <<EOF

$SFM_BEGIN
[ -f "$FUNCTIONS_FILE" ] && source "$FUNCTIONS_FILE"
[ -f "$ALIASES_FILE" ] && source "$ALIASES_FILE"
$SFM_END
EOF

  printf '%b\n\n' "${GREEN}✓${NC} Updated $SHELL_CONFIG"
  log_info "Updated shell config: $SHELL_CONFIG"
}

# ---------------------------
# Rollback / uninstall
# ---------------------------
rollback_sfm() {
  printf '\n%b\n\n' "${YELLOW}${BOLD}SFM ROLLBACK${NC}"

  if ! ask_yn "This will remove SFM configuration. Continue?"; then
    printf '%b\n' "Rollback cancelled"
    return 0
  fi

  local rollback_success=true

  # fish: remove drop-in
  if [[ "$SHELL_NAME" == "fish" ]]; then
    if [[ -f "$SHELL_CONFIG" ]]; then
      rm -f "$SHELL_CONFIG" || rollback_success=false
      printf '%b\n' "${GREEN}✓${NC} Removed: $SHELL_CONFIG"
      log_info "Removed fish drop-in: $SHELL_CONFIG"
    fi
  else
    # restore latest backup if exists
    local backup_file=""
    backup_file="$(ls -t "${SHELL_CONFIG}.sfm-backup-"* 2>/dev/null | head -1 || true)"
    if [[ -n "$backup_file" ]]; then
      if ask_yn "Restore from backup: ${backup_file##*/}?"; then
        if cp "$backup_file" "$SHELL_CONFIG"; then
          printf '%b\n' "${GREEN}✓${NC} Restored shell config"
          log_info "Restored shell config from backup"
        else
          printf '%b\n' "${RED}✗${NC} Failed to restore shell config"
          log_error "Failed to restore shell config"
          rollback_success=false
        fi
      fi
    else
      # remove marker block if present
      if grep -qF "$SFM_BEGIN" "$SHELL_CONFIG" 2>/dev/null; then
        sed -i.bak "/$(printf '%s' "$SFM_BEGIN" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/,/$(printf '%s' "$SFM_END" | sed 's/[.[\*^$(){}?+|/]/\\&/g')/d" "$SHELL_CONFIG" || true
        rm -f "${SHELL_CONFIG}.bak" || true
        printf '%b\n' "${GREEN}✓${NC} Removed SFM block from $SHELL_CONFIG"
        log_info "Removed SFM block from $SHELL_CONFIG"
      fi
    fi
  fi

  if ask_yn "Remove SFM directory ($SFM_DIR)?"; then
    if [[ -d "$SFM_DIR" ]]; then
      rm -rf "$SFM_DIR" || rollback_success=false
      printf '%b\n' "${GREEN}✓${NC} Removed $SFM_DIR"
      # can't log after deleting dir reliably
    fi
  fi

  printf '\n'
  if [[ "$rollback_success" == true ]]; then
    printf '%b\n\n' "${GREEN}✓ Rollback complete. Restart your terminal.${NC}"
  else
    printf '%b\n\n' "${YELLOW}⚠ Rollback finished with errors.${NC}"
  fi
}

# ---------------------------
# Main setup
# ---------------------------
setup_sfm() {
  printf '\n%b\n\n' "${CYAN}${BOLD}SFM - Shell Function Manager${NC}"

  ensure_log_ready
  log "SFM Setup Started"

  detect_distro
  detect_package_manager
  detect_shell
  check_dependencies
  generate_functions
  generate_aliases
  update_shell_config

  printf '%b\n\n' "${GREEN}${BOLD}✓ SFM setup complete!${NC}"
  printf '%b\n' "${BOLD}Functions:${NC} extract, mkcd, psgrep, backup, myip, portcheck"
  printf '%b\n\n' "${BOLD}Activate:${NC}"

  if [[ "$SHELL_NAME" == "fish" ]]; then
    printf '%b\n' "  fish will auto-load it. Restart terminal or run: ${CYAN}exec fish${NC}"
  else
    printf '%b\n' "  ${CYAN}source $SHELL_CONFIG${NC}"
  fi

  printf '\n'
  log "SFM Setup Completed Successfully"
}

# ---------------------------
# Arg parsing
# ---------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch|-b)
      BATCH_MODE=true
      YES_TO_ALL=true
      shift
      ;;
    --yes|-y)
      YES_TO_ALL=true
      shift
      ;;
    --shell)
      TARGET_SHELL_OVERRIDE="${2:-}"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    --uninstall|--rollback)
      ensure_log_ready
      detect_shell
      rollback_sfm
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

setup_sfm