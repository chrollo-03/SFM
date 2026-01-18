#!/bin/bash

set -euo pipefail

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SFM_DIR="$HOME/.sfm"
FUNCTIONS_FILE="$SFM_DIR/functions"
ALIASES_FILE="$SFM_DIR/aliases"
CONFIG_FILE="$SFM_DIR/config"
LOG_FILE="$SFM_DIR/setup.log"

# Global variables
SHELL_NAME=""
SHELL_CONFIG=""
DISTRO=""
PKG_MANAGER=""
PKG_INSTALL_CMD=""

# Create directory structure
mkdir -p "$SFM_DIR"
touch "$LOG_FILE"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Clear screen and show header
show_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║      SFM (Shell Function Manager) Setup - Enhanced         ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "${YELLOW}This wizard will configure your shell environment.${NC}"
    echo ""
}

# Detect distribution
detect_distro() {
    log "Detecting distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        echo -e "${GREEN}✓${NC} Distribution: ${BOLD}$PRETTY_NAME${NC}"
    else
        DISTRO="unknown"
        echo -e "${YELLOW}⚠${NC} Could not detect distribution"
    fi
    
    log "Distribution: $DISTRO"
}

# Detect package manager
detect_package_manager() {
    log "Detecting package manager..."
    
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL_CMD="sudo apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL_CMD="sudo dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL_CMD="sudo yum install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL_CMD="sudo zypper install -y"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
        PKG_INSTALL_CMD="sudo apk add"
    else
        PKG_MANAGER="none"
        echo -e "${YELLOW}⚠${NC} No package manager detected"
        return 1
    fi
    
    echo -e "${GREEN}✓${NC} Package manager: ${BOLD}$PKG_MANAGER${NC}"
    log "Package manager: $PKG_MANAGER"
    return 0
}

# Detect shell
detect_shell() {
    log "Detecting shell..."
    
    if [ -z "${SHELL:-}" ]; then
        echo -e "${RED}Error: Unable to determine shell${NC}"
        log "ERROR: Unable to determine shell"
        exit 1
    fi
    
    case "$SHELL" in
        */bash)
            SHELL_NAME="bash"
            SHELL_CONFIG="$HOME/.bashrc"
            FUNCTIONS_FILE="${FUNCTIONS_FILE}.sh"
            ALIASES_FILE="${ALIASES_FILE}.sh"
            ;;
        */zsh)
            SHELL_NAME="zsh"
            SHELL_CONFIG="$HOME/.zshrc"
            FUNCTIONS_FILE="${FUNCTIONS_FILE}.sh"
            ALIASES_FILE="${ALIASES_FILE}.sh"
            ;;
        */fish)
            SHELL_NAME="fish"
            SHELL_CONFIG="$HOME/.config/fish/config.fish"
            FUNCTIONS_FILE="${FUNCTIONS_FILE}.fish"
            ALIASES_FILE="${ALIASES_FILE}.fish"
            mkdir -p "$HOME/.config/fish"
            ;;
        *)
            echo -e "${RED}Unsupported shell: $SHELL${NC}"
            log "ERROR: Unsupported shell: $SHELL"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✓${NC} Shell: ${BOLD}$SHELL_NAME${NC}"
    echo -e "${GREEN}✓${NC} Config: ${BOLD}$SHELL_CONFIG${NC}"
    log "Shell: $SHELL_NAME, Config: $SHELL_CONFIG"
    echo ""
}

# Check and install dependencies
check_dependencies() {
    echo -e "${BOLD}Checking dependencies...${NC}"
    log "Checking dependencies..."
    
    local deps="curl wget unzip tar gzip bzip2"
    local missing_deps=()
    
    for dep in $deps; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
            echo -e "${YELLOW}⚠${NC} Missing: $dep"
        else
            echo -e "${GREEN}✓${NC} Found: $dep"
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        if [ "$PKG_MANAGER" != "none" ]; then
            if ask_yn "Install missing dependencies (${missing_deps[*]})?"; then
                for dep in "${missing_deps[@]}"; do
                    echo -e "${CYAN}Installing $dep...${NC}"
                    if $PKG_INSTALL_CMD "$dep" >> "$LOG_FILE" 2>&1; then
                        echo -e "${GREEN}✓${NC} Installed: $dep"
                        log "Installed: $dep"
                    else
                        echo -e "${RED}✗${NC} Failed to install: $dep"
                        log "ERROR: Failed to install: $dep"
                    fi
                done
            fi
        else
            echo -e "${YELLOW}Please install manually: ${missing_deps[*]}${NC}"
        fi
    fi
    echo ""
}

# Ask yes/no question
ask_yn() {
    local prompt="$1"
    local response
    
    while true; do
        read -p "$(echo -e ${CYAN}${prompt}${NC} [y/n]: )" response
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo -e "${RED}Please answer y or n${NC}" ;;
        esac
    done
}

# Show function description
show_function() {
    local title="$1"
    local description="$2"
    local code="$3"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${title}${NC}"
    echo -e "${description}"
    echo ""
    echo -e "${YELLOW}Preview:${NC}"
    echo -e "${code}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Initialize files based on shell
init_files() {
    log "Initializing configuration files for $SHELL_NAME..."
    
    if [ "$SHELL_NAME" = "fish" ]; then
        cat > "$FUNCTIONS_FILE" << 'EOF'
# SFM Functions - Auto-generated for Fish
# Edit manually or re-run the wizard

EOF
        cat > "$ALIASES_FILE" << 'EOF'
# SFM Aliases - Auto-generated for Fish
# Edit manually or re-run the wizard

EOF
    else
        cat > "$FUNCTIONS_FILE" << 'EOF'
#!/bin/bash
# SFM Functions - Auto-generated
# Edit manually or re-run the wizard

EOF
        cat > "$ALIASES_FILE" << 'EOF'
#!/bin/bash
# SFM Aliases - Auto-generated
# Edit manually or re-run the wizard

EOF
    fi
}

# Add function based on shell type
add_function() {
    local func_name="$1"
    local bash_code="$2"
    local fish_code="$3"
    
    if [ "$SHELL_NAME" = "fish" ]; then
        echo "$fish_code" >> "$FUNCTIONS_FILE"
    else
        echo "$bash_code" >> "$FUNCTIONS_FILE"
    fi
    log "Added function: $func_name"
}

# Add alias based on shell type
add_alias() {
    local alias_name="$1"
    local alias_value="$2"
    
    if [ "$SHELL_NAME" = "fish" ]; then
        echo "alias $alias_name '$alias_value'" >> "$ALIASES_FILE"
    else
        echo "alias $alias_name='$alias_value'" >> "$ALIASES_FILE"
    fi
    log "Added alias: $alias_name"
}

# Configure functions
configure_functions() {
    echo -e "${BOLD}Configuring shell functions:${NC}"
    echo ""
    sleep 1

    # Function 1: Extract archives
    show_function \
        "📦 Extract - Universal Archive Extractor" \
        "Automatically detects and extracts any archive format\nUsage: extract <file>" \
        "extract file.tar.gz"

    if ask_yn "Add the 'extract' function?"; then
        add_function "extract" \
'# Universal archive extractor
extract() {
    if [ -z "$1" ]; then
        echo "Usage: extract <file>"
        return 1
    fi
    if [ ! -f "$1" ]; then
        echo "Error: '\''$1'\'' is not a valid file"
        return 1
    fi
    case "$1" in
        *.tar.bz2)   tar xjf "$1"     ;;
        *.tar.gz)    tar xzf "$1"     ;;
        *.bz2)       bunzip2 "$1"     ;;
        *.rar)       unrar x "$1"     ;;
        *.gz)        gunzip "$1"      ;;
        *.tar)       tar xf "$1"      ;;
        *.tbz2)      tar xjf "$1"     ;;
        *.tgz)       tar xzf "$1"     ;;
        *.zip)       unzip "$1"       ;;
        *.Z)         uncompress "$1"  ;;
        *.7z)        7z x "$1"        ;;
        *.tar.xz)    tar xJf "$1"     ;;
        *.xz)        unxz "$1"        ;;
        *)           echo "Error: '\''$1'\'' cannot be extracted via extract()" ;;
    esac
}
' \
'# Universal archive extractor
function extract
    if test (count $argv) -eq 0
        echo "Usage: extract <file>"
        return 1
    end
    if not test -f $argv[1]
        echo "Error: '\''$argv[1]'\'' is not a valid file"
        return 1
    end
    switch $argv[1]
        case "*.tar.bz2"
            tar xjf $argv[1]
        case "*.tar.gz"
            tar xzf $argv[1]
        case "*.bz2"
            bunzip2 $argv[1]
        case "*.gz"
            gunzip $argv[1]
        case "*.tar"
            tar xf $argv[1]
        case "*.zip"
            unzip $argv[1]
        case "*.7z"
            7z x $argv[1]
        case "*.tar.xz"
            tar xJf $argv[1]
        case "*"
            echo "Error: '\''$argv[1]'\'' cannot be extracted"
    end
end
'
        echo -e "${GREEN}✓${NC} Added extract function"
        
        if ask_yn "  Add alias 'ex' for extract?"; then
            add_alias "ex" "extract"
            echo -e "${GREEN}  ✓${NC} Added alias: ex"
        fi
    fi
    echo ""

    # Function 2: mkcd
    show_function \
        "📁 Mkcd - Make Directory and Enter" \
        "Creates a directory and immediately changes into it\nUsage: mkcd <dirname>" \
        "mkcd new-project"

    if ask_yn "Add the 'mkcd' function?"; then
        add_function "mkcd" \
'# Create directory and cd into it
mkcd() {
    if [ -z "$1" ]; then
        echo "Usage: mkcd <directory>"
        return 1
    fi
    mkdir -p "$1" && cd "$1"
}
' \
'# Create directory and cd into it
function mkcd
    if test (count $argv) -eq 0
        echo "Usage: mkcd <directory>"
        return 1
    end
    mkdir -p $argv[1]; and cd $argv[1]
end
'
        echo -e "${GREEN}✓${NC} Added mkcd function"
    fi
    echo ""

    # Function 3: psgrep
    show_function \
        "🔍 Psgrep - Find Process by Name" \
        "Searches running processes by name\nUsage: psgrep <process_name>" \
        "psgrep nginx"

    if ask_yn "Add the 'psgrep' function?"; then
        add_function "psgrep" \
'# Find process by name
psgrep() {
    if [ -z "$1" ]; then
        echo "Usage: psgrep <process_name>"
        return 1
    fi
    ps aux | grep -v grep | grep -i -e VSZ -e "$1"
}
' \
'# Find process by name
function psgrep
    if test (count $argv) -eq 0
        echo "Usage: psgrep <process_name>"
        return 1
    end
    ps aux | grep -v grep | grep -i -e VSZ -e $argv[1]
end
'
        echo -e "${GREEN}✓${NC} Added psgrep function"
        
        if ask_yn "  Add alias 'psg' for psgrep?"; then
            add_alias "psg" "psgrep"
            echo -e "${GREEN}  ✓${NC} Added alias: psg"
        fi
    fi
    echo ""

    # Function 4: backup
    show_function \
        "💾 Backup - Quick File Backup" \
        "Creates a timestamped backup of a file or directory\nUsage: backup <file_or_dir>" \
        "backup important.conf"

    if ask_yn "Add the 'backup' function?"; then
        add_function "backup" \
'# Quick backup with timestamp
backup() {
    if [ -z "$1" ]; then
        echo "Usage: backup <file_or_directory>"
        return 1
    fi
    if [ -e "$1" ]; then
        local backup_name="${1}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -r "$1" "$backup_name"
        echo "Backup created: $backup_name"
    else
        echo "Error: $1 does not exist"
        return 1
    fi
}
' \
'# Quick backup with timestamp
function backup
    if test (count $argv) -eq 0
        echo "Usage: backup <file_or_directory>"
        return 1
    end
    if test -e $argv[1]
        set backup_name "$argv[1].backup."(date +%Y%m%d_%H%M%S)
        cp -r $argv[1] $backup_name
        echo "Backup created: $backup_name"
    else
        echo "Error: $argv[1] does not exist"
        return 1
    end
end
'
        echo -e "${GREEN}✓${NC} Added backup function"
        
        if ask_yn "  Add alias 'bak' for backup?"; then
            add_alias "bak" "backup"
            echo -e "${GREEN}  ✓${NC} Added alias: bak"
        fi
    fi
    echo ""

    # Function 5: myip
    show_function \
        "🌐 Myip - Show Network Information" \
        "Displays local and public IP addresses\nUsage: myip" \
        "myip"

    if ask_yn "Add the 'myip' function?"; then
        add_function "myip" \
'# Show network information
myip() {
    echo "Local IP addresses:"
    if command -v hostname &> /dev/null; then
        hostname -I 2>/dev/null || ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '\''{print $2}'\''
    else
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '\''{print $2}'\''
    fi
    echo ""
    echo "Public IP address:"
    if command -v curl &> /dev/null; then
        curl -s ifconfig.me || curl -s icanhazip.com || echo "Unable to determine public IP"
    elif command -v wget &> /dev/null; then
        wget -qO- ifconfig.me || echo "Unable to determine public IP"
    else
        echo "curl or wget required to determine public IP"
    fi
}
' \
'# Show network information
function myip
    echo "Local IP addresses:"
    if command -v hostname &> /dev/null
        hostname -I 2>/dev/null; or ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '\''{print $2}'\''
    else
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '\''{print $2}'\''
    end
    echo ""
    echo "Public IP address:"
    if command -v curl &> /dev/null
        curl -s ifconfig.me; or echo "Unable to determine public IP"
    else if command -v wget &> /dev/null
        wget -qO- ifconfig.me; or echo "Unable to determine public IP"
    else
        echo "curl or wget required"
    end
end
'
        echo -e "${GREEN}✓${NC} Added myip function"
    fi
    echo ""

    # Function 6: portcheck
    show_function \
        "🔌 Portcheck - Check Port Status" \
        "Checks if a specific port is listening (requires sudo)\nUsage: portcheck <port>" \
        "portcheck 80"

    if ask_yn "Add the 'portcheck' function?"; then
        add_function "portcheck" \
'# Check what'\''s listening on a port
portcheck() {
    if [ -z "$1" ]; then
        echo "Usage: portcheck <port>"
        return 1
    fi
    echo "Checking port $1..."
    if command -v lsof &> /dev/null; then
        sudo lsof -i ":$1" || echo "Port $1 is not in use"
    elif command -v ss &> /dev/null; then
        sudo ss -tulpn | grep ":$1" || echo "Port $1 is not in use"
    else
        echo "lsof or ss required for port checking"
        return 1
    fi
}
' \
'# Check what'\''s listening on a port
function portcheck
    if test (count $argv) -eq 0
        echo "Usage: portcheck <port>"
        return 1
    end
    echo "Checking port $argv[1]..."
    if command -v lsof &> /dev/null
        sudo lsof -i ":$argv[1]"; or echo "Port $argv[1] is not in use"
    else if command -v ss &> /dev/null
        sudo ss -tulpn | grep ":$argv[1]"; or echo "Port $argv[1] is not in use"
    else
        echo "lsof or ss required"
        return 1
    end
end
'
        echo -e "${GREEN}✓${NC} Added portcheck function"
    fi
    echo ""

    # Custom function builder
    if ask_yn "Would you like to create a custom function?"; then
        create_custom_function
    fi
}

# Create custom function interactively
create_custom_function() {
    echo ""
    echo -e "${MAGENTA}${BOLD}Custom Function Builder${NC}"
    echo -e "${YELLOW}Leave name blank to finish${NC}"
    echo ""
    
    while true; do
        read -p "$(echo -e ${CYAN}Function name:${NC} )" func_name
        [ -z "$func_name" ] && break
        
        read -p "$(echo -e ${CYAN}Description:${NC} )" func_desc
        read -p "$(echo -e ${CYAN}Command to execute:${NC} )" func_cmd
        
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$FUNCTIONS_FILE" << EOF

# $func_desc
function $func_name
    $func_cmd
end
EOF
        else
            cat >> "$FUNCTIONS_FILE" << EOF

# $func_desc
$func_name() {
    $func_cmd
}
EOF
        fi
        
        echo -e "${GREEN}✓${NC} Added custom function: $func_name"
        log "Added custom function: $func_name"
        echo ""
        
        if ! ask_yn "Add another custom function?"; then
            break
        fi
    done
}

# Configure aliases
configure_aliases() {
    echo -e "${BOLD}Configuring aliases:${NC}"
    echo ""

    # Navigation aliases
    echo -e "${BLUE}Navigation shortcuts:${NC}"
    if ask_yn "Add quick navigation aliases? (.. ... .... etc.)"; then
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$ALIASES_FILE" << 'EOF'

# Navigation
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'
EOF
        else
            cat >> "$ALIASES_FILE" << 'EOF'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
EOF
        fi
        echo -e "${GREEN}✓${NC} Added navigation aliases"
        log "Added navigation aliases"
    fi
    echo ""

    # Safety aliases
    echo -e "${BLUE}Safety aliases:${NC}"
    if ask_yn "Add safe rm/cp/mv aliases? (interactive prompts)"; then
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$ALIASES_FILE" << 'EOF'

# Safety
alias rm 'rm -i'
alias cp 'cp -i'
alias mv 'mv -i'
EOF
        else
            cat >> "$ALIASES_FILE" << 'EOF'

# Safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOF
        fi
        echo -e "${GREEN}✓${NC} Added safety aliases"
        log "Added safety aliases"
    fi
    echo ""

    # ls aliases
    echo -e "${BLUE}ls variants:${NC}"
    if ask_yn "Add enhanced ls aliases? (ll, la, lt, etc.)"; then
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$ALIASES_FILE" << 'EOF'

# ls variants
alias ll 'ls -lh'
alias la 'ls -lAh'
alias lt 'ls -lth'
alias l 'ls -CF'
alias lsd 'ls -l | grep "^d"'
EOF
        else
            cat >> "$ALIASES_FILE" << 'EOF'

# ls variants
alias ll='ls -lh'
alias la='ls -lAh'
alias lt='ls -lth'
alias l='ls -CF'
alias lsd='ls -l | grep "^d"'
EOF
        fi
        echo -e "${GREEN}✓${NC} Added ls aliases"
        log "Added ls aliases"
    fi
    echo ""

    # Git aliases
    if command -v git &> /dev/null; then
        echo -e "${BLUE}Git shortcuts:${NC}"
        if ask_yn "Add common git aliases? (gs, ga, gc, gp, etc.)"; then
            if [ "$SHELL_NAME" = "fish" ]; then
                cat >> "$ALIASES_FILE" << 'EOF'

# Git shortcuts
alias gs 'git status'
alias ga 'git add'
alias gc 'git commit'
alias gp 'git push'
alias gl 'git log --oneline --graph --decorate'
alias gd 'git diff'
alias gco 'git checkout'
alias gb 'git branch'
EOF
            else
                cat >> "$ALIASES_FILE" << 'EOF'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
EOF
            fi
            echo -e "${GREEN}✓${NC} Added git aliases"
            log "Added git aliases"
        fi
        echo ""
    fi

    # System monitoring aliases
    echo -e "${BLUE}System monitoring:${NC}"
    if ask_yn "Add system monitoring aliases? (df, free, htop)"; then
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$ALIASES_FILE" << 'EOF'

# System monitoring
alias df 'df -h'
alias free 'free -h'
alias psa 'ps auxf'
alias meminfo 'free -m -l -t'
alias cpuinfo 'lscpu'
EOF
        else
            cat >> "$ALIASES_FILE" << 'EOF'

# System monitoring
alias df='df -h'
alias free='free -h'
alias psa='ps auxf'
alias meminfo='free -m -l -t'
alias cpuinfo='lscpu'
EOF
        fi
        echo -e "${GREEN}✓${NC} Added system aliases"
        log "Added system aliases"
    fi
    echo ""

    # Network aliases
    echo -e "${BLUE}Network utilities:${NC}"
    if ask_yn "Add network utility aliases?"; then
        if [ "$SHELL_NAME" = "fish" ]; then
            cat >> "$ALIASES_FILE" << 'EOF'

# Network utilities
alias ports 'netstat -tulanp'
alias ping 'ping -c 5'
alias wget 'wget -c'
EOF
        else
            cat >> "$ALIASES_FILE" << 'EOF'

# Network utilities
alias ports='netstat -tulanp'
alias ping='ping -c 5'
alias wget='wget -c'
EOF
        fi
        echo -e "${GREEN}✓${NC} Added network aliases"
        log "Added network aliases"
    fi
    echo ""
}

# Update shell configuration
update_shell_config() {
    echo -e "${BOLD}Updating shell configuration...${NC}"
    echo ""
    
    if ask_yn "Automatically source SFM in your $SHELL_CONFIG?"; then
        # Backup existing config
        if [ -f "$SHELL_CONFIG" ]; then
            cp "$SHELL_CONFIG" "${SHELL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${GREEN}✓${NC} Backed up existing config"
        fi
        
        # Check if already configured
        if grep -q "SFM - Shell Function Manager" "$SHELL_CONFIG" 2>/dev/null; then
            echo -e "${YELLOW}⚠${NC} SFM already configured in $SHELL_CONFIG"
            log "SFM already in shell config"
        else
            if [ "$SHELL_NAME" = "fish" ]; then
                cat >> "$SHELL_CONFIG" << EOF

# SFM - Shell Function Manager
if test -f "$FUNCTIONS_FILE"
    source "$FUNCTIONS_FILE"
end
if test -f "$ALIASES_FILE"
    source "$ALIASES_FILE"
end
EOF
            else
                cat >> "$SHELL_CONFIG" << EOF

# SFM - Shell Function Manager
[ -f "$FUNCTIONS_FILE" ] && source "$FUNCTIONS_FILE"
[ -f "$ALIASES_FILE" ] && source "$ALIASES_FILE"
EOF
            fi
            echo -e "${GREEN}✓${NC} Updated $SHELL_CONFIG"
            log "Updated shell config: $SHELL_CONFIG"
        fi
    else
        echo -e "${YELLOW}Skipped shell configuration update${NC}"
        echo ""
        echo -e "To manually enable SFM, add these lines to your $SHELL_CONFIG:"
        if [ "$SHELL_NAME" = "fish" ]; then
            echo -e "${CYAN}source \"$FUNCTIONS_FILE\"${NC}"
            echo -e "${CYAN}source \"$ALIASES_FILE\"${NC}"
        else
            echo -e "${CYAN}[ -f \"$FUNCTIONS_FILE\" ] && source \"$FUNCTIONS_FILE\"${NC}"
            echo -e "${CYAN}[ -f \"$ALIASES_FILE\" ] && source \"$ALIASES_FILE\"${NC}"
        fi
    fi
}

# Show summary
show_summary() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                  Setup Complete! 🎉                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BOLD}Configuration Summary:${NC}"
    echo -e "  Shell:       ${GREEN}$SHELL_NAME${NC}"
    echo -e "  Distro:      ${GREEN}$DISTRO${NC}"
    echo -e "  Pkg Manager: ${GREEN}$PKG_MANAGER${NC}"
    echo ""
    
    echo -e "${BOLD}Your SFM files:${NC}"
    echo -e "  Functions: ${GREEN}$FUNCTIONS_FILE${NC}"
    echo -e "  Aliases:   ${GREEN}$ALIASES_FILE${NC}"
    echo -e "  Config:    ${GREEN}$SHELL_CONFIG${NC}"
    echo -e "  Log:       ${GREEN}$LOG_FILE${NC}"
    echo ""
    
    echo -e "${BOLD}To apply changes:${NC}"
    echo -e "  ${YELLOW}source $SHELL_CONFIG${NC}"
    echo -e "  ${YELLOW}# or restart your terminal${NC}"
    echo ""
    
    echo -e "${BOLD}Quick Reference:${NC}"
    if grep -q "extract" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}extract${NC} <file>     - Extract any archive"
    fi
    if grep -q "mkcd" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}mkcd${NC} <dir>        - Create and enter directory"
    fi
    if grep -q "backup" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}backup${NC} <file>     - Create timestamped backup"
    fi
    if grep -q "myip" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}myip${NC}              - Show IP addresses"
    fi
    if grep -q "portcheck" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}portcheck${NC} <port>   - Check port status"
    fi
    if grep -q "psgrep" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "  ${CYAN}psgrep${NC} <name>     - Find process by name"
    fi
    echo ""
    
    echo -e "${BOLD}Manage SFM:${NC}"
    echo -e "  Edit functions: ${CYAN}${EDITOR:-vim} $FUNCTIONS_FILE${NC}"
    echo -e "  Edit aliases:   ${CYAN}${EDITOR:-vim} $ALIASES_FILE${NC}"
    echo -e "  Re-run wizard:  ${CYAN}bash $0${NC}"
    echo -e "  View log:       ${CYAN}cat $LOG_FILE${NC}"
    echo ""
    
    # Save config summary
    cat > "$CONFIG_FILE" << EOF
# SFM Configuration Summary
# Generated: $(date)

SHELL_NAME=$SHELL_NAME
SHELL_CONFIG=$SHELL_CONFIG
DISTRO=$DISTRO
PKG_MANAGER=$PKG_MANAGER
FUNCTIONS_FILE=$FUNCTIONS_FILE
ALIASES_FILE=$ALIASES_FILE
INSTALL_DATE=$(date +%Y-%m-%d)
EOF
    
    log "Setup completed successfully"
}

# Rollback function
rollback_sfm() {
    echo -e "${YELLOW}${BOLD}SFM Rollback${NC}"
    echo ""
    
    if ! ask_yn "This will remove SFM configuration. Continue?"; then
        echo "Rollback cancelled"
        return 0
    fi
    
    # Find and restore backup
    local backup_file=$(ls -t "${SHELL_CONFIG}.backup."* 2>/dev/null | head -1)
    if [ -n "$backup_file" ]; then
        if ask_yn "Restore shell config from backup ($backup_file)?"; then
            cp "$backup_file" "$SHELL_CONFIG"
            echo -e "${GREEN}✓${NC} Restored $SHELL_CONFIG"
            log "Restored shell config from $backup_file"
        fi
    fi
    
    # Remove SFM lines from shell config
    if grep -q "SFM - Shell Function Manager" "$SHELL_CONFIG" 2>/dev/null; then
        if [ "$SHELL_NAME" = "fish" ]; then
            sed -i '/# SFM - Shell Function Manager/,/end/d' "$SHELL_CONFIG"
        else
            sed -i '/# SFM - Shell Function Manager/,+2d' "$SHELL_CONFIG"
        fi
        echo -e "${GREEN}✓${NC} Removed SFM from $SHELL_CONFIG"
        log "Removed SFM from shell config"
    fi
    
    # Ask about removing SFM directory
    if ask_yn "Remove SFM directory ($SFM_DIR)?"; then
        rm -rf "$SFM_DIR"
        echo -e "${GREEN}✓${NC} Removed $SFM_DIR"
        log "Removed SFM directory"
    fi
    
    echo ""
    echo -e "${GREEN}Rollback complete. Please restart your terminal.${NC}"
}

# Check if this is an update/reinstall
check_existing_install() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}⚠${NC} Existing SFM installation detected"
        echo ""
        . "$CONFIG_FILE"
        echo -e "Previous install: ${CYAN}$INSTALL_DATE${NC}"
        echo ""
        
        PS3="$(echo -e ${CYAN}Choose an option:${NC} )"
        options=("Update/Reconfigure" "Rollback/Uninstall" "Exit")
        select opt in "${options[@]}"; do
            case $opt in
                "Update/Reconfigure")
                    echo -e "${GREEN}Proceeding with update...${NC}"
                    echo ""
                    return 0
                    ;;
                "Rollback/Uninstall")
                    rollback_sfm
                    exit 0
                    ;;
                "Exit")
                    echo "Exiting..."
                    exit 0
                    ;;
                *) echo -e "${RED}Invalid option${NC}";;
            esac
        done
    fi
}

# Main execution
main() {
    show_header
    
    # System detection
    detect_distro
    detect_package_manager
    detect_shell
    
    # Check for existing installation
    check_existing_install
    
    # Dependency check
    check_dependencies
    
    # Initialize files
    init_files
    
    # Configuration
    configure_functions
    configure_aliases
    
    # Update shell
    update_shell_config
    
    # Show summary
    show_summary
}

# Trap errors
trap 'echo -e "${RED}Error occurred. Check $LOG_FILE for details${NC}"; log "ERROR: Script failed"' ERR

# Run main
main