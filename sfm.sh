#!/bin/bash

set -euo pipefail

# Configuration
SFM_DIR="$HOME/.sfm"
FUNCTIONS_FILE="$SFM_DIR/functions"
ALIASES_FILE="$SFM_DIR/aliases"
CONFIG_FILE="$SFM_DIR/config"
LOG_FILE="$SFM_DIR/setup.log"
TEMP_DIR="/tmp/sfm.$$"

# Global variables
SHELL_NAME=""
SHELL_CONFIG=""
DISTRO=""
PKG_MANAGER=""
PKG_INSTALL_CMD=""
TUI_TOOL=""

# Arrays to track selections
declare -a SELECTED_FUNCTIONS=()
declare -a SELECTED_ALIASES=()

# Cleanup on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Create directory structure
mkdir -p "$SFM_DIR" "$TEMP_DIR"
touch "$LOG_FILE"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Colors for basic mode
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Detect package manager (silent)
detect_package_manager_silent() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL_CMD="sudo apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL_CMD="sudo dnf install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL_CMD="sudo pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL_CMD="sudo zypper install -y"
    else
        PKG_MANAGER="none"
        PKG_INSTALL_CMD=""
    fi
    log "Package manager: $PKG_MANAGER"
}

# Detect and install TUI tool
setup_tui() {
    log "Setting up TUI..."
    
    # Check for available TUI tools
    if command -v dialog &> /dev/null; then
        TUI_TOOL="dialog"
        log "Using dialog for TUI"
        return 0
    elif command -v whiptail &> /dev/null; then
        TUI_TOOL="whiptail"
        log "Using whiptail for TUI"
        return 0
    fi
    
    # Try to install dialog
    detect_package_manager_silent
    
    if [ "$PKG_MANAGER" != "none" ] && [ -n "$PKG_INSTALL_CMD" ]; then
        echo "Installing dialog for better user interface..."
        if $PKG_INSTALL_CMD dialog &>> "$LOG_FILE"; then
            TUI_TOOL="dialog"
            log "Installed dialog"
            return 0
        fi
    fi
    
    # Fallback to basic mode
    TUI_TOOL="basic"
    log "Using basic mode (no TUI)"
    echo "Running in basic mode (no TUI tools available)"
    sleep 1
}

# Detect distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$PRETTY_NAME"
    else
        DISTRO="Unknown"
    fi
    log "Distribution: $DISTRO"
}

# Detect shell
detect_shell() {
    log "Detecting shell..."
    
    local current_shell="${SHELL:-/bin/bash}"
    
    case "$current_shell" in
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
            SHELL_NAME="bash"
            SHELL_CONFIG="$HOME/.bashrc"
            FUNCTIONS_FILE="${FUNCTIONS_FILE}.sh"
            ALIASES_FILE="${ALIASES_FILE}.sh"
            ;;
    esac
    
    log "Shell: $SHELL_NAME, Config: $SHELL_CONFIG"
}

# TUI helper functions
tui_msgbox() {
    local title="$1"
    local message="$2"
    
    case "$TUI_TOOL" in
        dialog)
            dialog --title "$title" --msgbox "$message" 15 70 2>/dev/null
            clear
            ;;
        whiptail)
            whiptail --title "$title" --msgbox "$message" 15 70 2>/dev/null
            clear
            ;;
        *)
            echo ""
            echo -e "${CYAN}${BOLD}=== $title ===${NC}"
            echo -e "$message"
            echo ""
            read -p "Press Enter to continue..." -r
            ;;
    esac
}

tui_yesno() {
    local title="$1"
    local question="$2"
    
    case "$TUI_TOOL" in
        dialog)
            dialog --title "$title" --yesno "$question" 8 60 2>/dev/null
            local result=$?
            clear
            return $result
            ;;
        whiptail)
            whiptail --title "$title" --yesno "$question" 8 60 2>/dev/null
            local result=$?
            clear
            return $result
            ;;
        *)
            while true; do
                echo ""
                read -p "$(echo -e ${CYAN}${question}${NC}) [y/n]: " -r response
                case "$response" in
                    [Yy]*) return 0 ;;
                    [Nn]*) return 1 ;;
                    *) echo -e "${RED}Please answer y or n${NC}" ;;
                esac
            done
            ;;
    esac
}

tui_menu() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    
    case "$TUI_TOOL" in
        dialog|whiptail)
            local menu_items=()
            local i=1
            for opt in "${options[@]}"; do
                menu_items+=("$i" "$opt")
                ((i++))
            done
            
            local choice
            if [ "$TUI_TOOL" = "dialog" ]; then
                choice=$(dialog --title "$title" --menu "$prompt" 20 70 15 "${menu_items[@]}" 2>&1 >/dev/tty)
            else
                choice=$(whiptail --title "$title" --menu "$prompt" 20 70 15 "${menu_items[@]}" 2>&1 >/dev/tty)
            fi
            
            local exit_code=$?
            clear
            
            if [ $exit_code -eq 0 ] && [ -n "$choice" ]; then
                echo "${options[$((choice-1))]}"
                return 0
            else
                return 1
            fi
            ;;
        *)
            echo ""
            echo -e "${CYAN}${BOLD}=== $title ===${NC}"
            echo -e "${YELLOW}$prompt${NC}"
            echo ""
            local i=1
            for opt in "${options[@]}"; do
                echo "  $i) $opt"
                ((i++))
            done
            echo ""
            while true; do
                read -p "Choice (1-${#options[@]}): " -r choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
                    echo "${options[$((choice-1))]}"
                    return 0
                else
                    echo -e "${RED}Invalid choice. Please enter 1-${#options[@]}${NC}"
                fi
            done
            ;;
    esac
}

tui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local options=("$@")
    
    case "$TUI_TOOL" in
        dialog|whiptail)
            local menu_items=()
            local i=1
            for opt in "${options[@]}"; do
                menu_items+=("$i" "$opt" "ON")
                ((i++))
            done
            
            local choices
            if [ "$TUI_TOOL" = "dialog" ]; then
                choices=$(dialog --title "$title" --checklist "$prompt" 20 70 15 "${menu_items[@]}" 2>&1 >/dev/tty)
            else
                choices=$(whiptail --title "$title" --checklist "$prompt" 20 70 15 "${menu_items[@]}" 2>&1 >/dev/tty)
            fi
            
            local exit_code=$?
            clear
            
            if [ $exit_code -eq 0 ]; then
                # Convert to array of selected items
                for choice in $choices; do
                    choice=$(echo "$choice" | tr -d '"')
                    echo "${options[$((choice-1))]}"
                done
                return 0
            else
                return 1
            fi
            ;;
        *)
            echo ""
            echo -e "${CYAN}${BOLD}=== $title ===${NC}"
            echo -e "${YELLOW}$prompt${NC}"
            echo -e "${YELLOW}(Enter numbers separated by spaces, or 'all' for all items)${NC}"
            echo ""
            local i=1
            for opt in "${options[@]}"; do
                echo "  $i) $opt"
                ((i++))
            done
            echo ""
            read -p "Choices: " -r -a choices
            
            if [ "${choices[0]}" = "all" ]; then
                printf '%s\n' "${options[@]}"
            else
                for choice in "${choices[@]}"; do
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
                        echo "${options[$((choice-1))]}"
                    fi
                done
            fi
            return 0
            ;;
    esac
}

tui_input() {
    local title="$1"
    local prompt="$2"
    local default="${3:-}"
    
    case "$TUI_TOOL" in
        dialog)
            local result
            result=$(dialog --title "$title" --inputbox "$prompt" 8 60 "$default" 2>&1 >/dev/tty)
            local exit_code=$?
            clear
            if [ $exit_code -eq 0 ]; then
                echo "$result"
                return 0
            else
                return 1
            fi
            ;;
        whiptail)
            local result
            result=$(whiptail --title "$title" --inputbox "$prompt" 8 60 "$default" 2>&1 >/dev/tty)
            local exit_code=$?
            clear
            if [ $exit_code -eq 0 ]; then
                echo "$result"
                return 0
            else
                return 1
            fi
            ;;
        *)
            echo ""
            if [ -n "$default" ]; then
                read -p "$(echo -e ${CYAN}${prompt}${NC}) [$default]: " -r result
                echo "${result:-$default}"
            else
                read -p "$(echo -e ${CYAN}${prompt}${NC}): " -r result
                echo "$result"
            fi
            return 0
            ;;
    esac
}

# Initialize files
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
    
    chmod +x "$FUNCTIONS_FILE" "$ALIASES_FILE"
    log "Initialized files: $FUNCTIONS_FILE, $ALIASES_FILE"
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

# System detection screen
system_detection_screen() {
    detect_distro
    detect_package_manager_silent
    
    local info="System Information:

Shell:          $SHELL_NAME
Config File:    $SHELL_CONFIG
Distribution:   $DISTRO
Pkg Manager:    $PKG_MANAGER

Files will be created:
  Functions:    $FUNCTIONS_FILE
  Aliases:      $ALIASES_FILE
  Config:       $CONFIG_FILE"
    
    tui_msgbox "System Detection" "$info"
}

# Configure functions menu
configure_functions_menu() {
    local selected
    selected=$(tui_checklist "Shell Functions" \
        "Select functions to install:" \
        "extract - Universal archive extractor" \
        "mkcd - Make directory and enter" \
        "psgrep - Find process by name" \
        "backup - Quick file backup" \
        "myip - Show network information" \
        "portcheck - Check port status")
    
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    local count=0
    # Process selected functions
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        
        case "$item" in
            "extract"*)
                add_extract_function
                ((count++))
                ;;
            "mkcd"*)
                add_mkcd_function
                ((count++))
                ;;
            "psgrep"*)
                add_psgrep_function
                ((count++))
                ;;
            "backup"*)
                add_backup_function
                ((count++))
                ;;
            "myip"*)
                add_myip_function
                ((count++))
                ;;
            "portcheck"*)
                add_portcheck_function
                ((count++))
                ;;
        esac
    done <<< "$selected"
    
    if [ $count -gt 0 ]; then
        tui_msgbox "Success" "$count function(s) added successfully!"
    fi
}

# Configure aliases menu
configure_aliases_menu() {
    local selected
    selected=$(tui_checklist "Shell Aliases" \
        "Select alias groups to install:" \
        "Navigation (.. ... ....)" \
        "Safety (rm -i, cp -i, mv -i)" \
        "ls variants (ll, la, lt)" \
        "Git shortcuts (gs, ga, gc, gp)" \
        "System monitoring (df, free, psa)" \
        "Network utilities (ports, ping)")
    
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    local count=0
    # Process selected alias groups
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        
        case "$item" in
            "Navigation"*)
                add_navigation_aliases
                ((count++))
                ;;
            "Safety"*)
                add_safety_aliases
                ((count++))
                ;;
            "ls variants"*)
                add_ls_aliases
                ((count++))
                ;;
            "Git shortcuts"*)
                add_git_aliases
                ((count++))
                ;;
            "System monitoring"*)
                add_system_aliases
                ((count++))
                ;;
            "Network utilities"*)
                add_network_aliases
                ((count++))
                ;;
        esac
    done <<< "$selected"
    
    if [ $count -gt 0 ]; then
        tui_msgbox "Success" "$count alias group(s) added successfully!"
    fi
}

# Custom function menu
create_custom_function_menu() {
    while true; do
        local func_name
        func_name=$(tui_input "Custom Function" "Function name (leave empty to cancel):")
        
        if [ $? -ne 0 ] || [ -z "$func_name" ]; then
            break
        fi
        
        local func_desc
        func_desc=$(tui_input "Custom Function" "Description:")
        
        local func_cmd
        func_cmd=$(tui_input "Custom Function" "Command to execute:")
        
        if [ -z "$func_cmd" ]; then
            tui_msgbox "Error" "Command cannot be empty"
            continue
        fi
        
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
        
        log "Added custom function: $func_name"
        tui_msgbox "Success" "Custom function '$func_name' added!"
        
        if ! tui_yesno "Continue" "Add another custom function?"; then
            break
        fi
    done
}

# Function implementations
add_extract_function() {
    add_function "extract" \
'# Universal archive extractor
extract() {
    if [ -z "$1" ]; then
        echo "Usage: extract <file>"
        return 1
    fi
    if [ ! -f "$1" ]; then
        echo "Error: '"'"'$1'"'"' not found"
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
        *)           echo "'"'"'$1'"'"' cannot be extracted" ;;
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
        echo "Error: '"'"'$argv[1]'"'"' not found"
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
            echo "'"'"'$argv[1]'"'"' cannot be extracted"
    end
end
'
}

add_mkcd_function() {
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
}

add_psgrep_function() {
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
}

add_backup_function() {
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
}

add_myip_function() {
    add_function "myip" \
'# Show network information
myip() {
    echo "Local IP addresses:"
    if command -v hostname &> /dev/null; then
        hostname -I 2>/dev/null || ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '"'"'{print $2}'"'"'
    else
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '"'"'{print $2}'"'"'
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
        hostname -I 2>/dev/null; or ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '"'"'{print $2}'"'"'
    else
        ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '"'"'{print $2}'"'"'
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
}

add_portcheck_function() {
    add_function "portcheck" \
'# Check what'"'"'s listening on a port
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
'# Check what'"'"'s listening on a port
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
}

# Alias implementations
add_navigation_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# Navigation aliases
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'
alias ..... 'cd ../../../..'
EOF
    else
        cat >> "$ALIASES_FILE" << 'EOF'

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
EOF
    fi
    log "Added navigation aliases"
}

add_safety_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# Safety aliases
alias rm 'rm -i'
alias cp 'cp -i'
alias mv 'mv -i'
alias ln 'ln -i'
EOF
    else
        cat >> "$ALIASES_FILE" << 'EOF'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias ln='ln -i'
EOF
    fi
    log "Added safety aliases"
}

add_ls_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# ls variant aliases
alias ll 'ls -lh'
alias la 'ls -lAh'
alias lt 'ls -lth'
alias l 'ls -CF'
alias lsd 'ls -l | grep "^d"'
EOF
    else
        cat >> "$ALIASES_FILE" << 'EOF'

# ls variant aliases
alias ll='ls -lh'
alias la='ls -lAh'
alias lt='ls -lth'
alias l='ls -CF'
alias lsd='ls -l | grep "^d"'
EOF
    fi
    log "Added ls aliases"
}

add_git_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# Git shortcut aliases
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

# Git shortcut aliases
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
    log "Added git aliases"
}

add_system_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# System monitoring aliases
alias df 'df -h'
alias free 'free -h'
alias psa 'ps auxf'
alias meminfo 'free -m -l -t'
alias cpuinfo 'lscpu'
EOF
    else
        cat >> "$ALIASES_FILE" << 'EOF'

# System monitoring aliases
alias df='df -h'
alias free='free -h'
alias psa='ps auxf'
alias meminfo='free -m -l -t'
alias cpuinfo='lscpu'
EOF
    fi
    log "Added system aliases"
}

add_network_aliases() {
    if [ "$SHELL_NAME" = "fish" ]; then
        cat >> "$ALIASES_FILE" << 'EOF'

# Network utility aliases
alias ports 'netstat -tulanp'
alias ping 'ping -c 5'
alias wget 'wget -c'
EOF
    else
        cat >> "$ALIASES_FILE" << 'EOF'

# Network utility aliases
alias ports='netstat -tulanp'
alias ping='ping -c 5'
alias wget='wget -c'
EOF
    fi
    log "Added network aliases"
}

# Finalize installation
finalize_installation() {
    log "Finalizing installation..."
    
    # Backup existing config
    if [ -f "$SHELL_CONFIG" ]; then
        local backup_file="${SHELL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SHELL_CONFIG" "$backup_file"
        log "Backed up $SHELL_CONFIG to $backup_file"
    fi
    
    # Check if already configured
    local already_configured=false
    if grep -q "SFM - Shell Function Manager" "$SHELL_CONFIG" 2>/dev/null; then
        already_configured=true
    fi
    
    # Add to shell config if not already there
    if [ "$already_configured" = false ]; then
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
        log "Added SFM to $SHELL_CONFIG"
    else
        log "SFM already configured in $SHELL_CONFIG"
    fi
    
    # Save config
    cat > "$CONFIG_FILE" << EOF
# SFM Configuration
SHELL_NAME=$SHELL_NAME
SHELL_CONFIG=$SHELL_CONFIG
DISTRO=$DISTRO
PKG_MANAGER=$PKG_MANAGER
INSTALL_DATE=$(date +%Y-%m-%d)
FUNCTIONS_FILE=$FUNCTIONS_FILE
ALIASES_FILE=$ALIASES_FILE
EOF
    
    log "Installation completed successfully"
    
    # Count functions and aliases
    local func_count=$(grep -c "^# " "$FUNCTIONS_FILE" 2>/dev/null || echo "0")
    local alias_count=$(grep -c "^alias " "$ALIASES_FILE" 2>/dev/null || echo "0")
    
    local success_msg="SFM Installation Complete!

Configuration Summary:
  Shell:          $SHELL_NAME
  Distribution:   $DISTRO
  Functions:      $func_count added
  Aliases:        $alias_count added

Files Created:
  Functions:      $FUNCTIONS_FILE
  Aliases:        $ALIASES_FILE
  Config:         $CONFIG_FILE
  Shell Config:   $SHELL_CONFIG

To Apply Changes:
  Run:  source $SHELL_CONFIG
  Or:   Restart your terminal

Management:
  Edit functions: \${EDITOR:-vim} $FUNCTIONS_FILE
  Edit aliases:   \${EDITOR:-vim} $ALIASES_FILE
  Re-run wizard:  bash $0
  View log:       cat $LOG_FILE"
    
    tui_msgbox "Installation Complete" "$success_msg"
}

# Main menu
show_main_menu() {
    while true; do
        local choice
        choice=$(tui_menu "SFM - Shell Function Manager" \
            "Main Menu - Select an option:" \
            "1. System Detection" \
            "2. Configure Shell Functions" \
            "3. Configure Shell Aliases" \
            "4. Add Custom Functions" \
            "5. Finalize & Install" \
            "6. Exit Without Installing")
        
        if [ $? -ne 0 ]; then
            if tui_yesno "Confirm Exit" "Exit without installing?"; then
                log "User cancelled installation"
                exit 0
            fi
            continue
        fi
        
        case "$choice" in
            "1. System Detection")
                system_detection_screen
                ;;
            "2. Configure Shell Functions")
                configure_functions_menu
                ;;
            "3. Configure Shell Aliases")
                configure_aliases_menu
                ;;
            "4. Add Custom Functions")
                create_custom_function_menu
                ;;
            "5. Finalize & Install")
                finalize_installation
                break
                ;;
            "6. Exit Without Installing")
                if tui_yesno "Confirm Exit" "Are you sure you want to exit without installing?"; then
                    log "User exited without installing"
                    exit 0
                fi
                ;;
        esac
    done
}

# Welcome screen
show_welcome() {
    local welcome_msg="Welcome to SFM - Shell Function Manager

This wizard will help you:
  • Detect your system configuration
  • Install useful shell functions
  • Configure helpful aliases
  • Customize your shell environment

Your shell: $SHELL_NAME
Config file: $SHELL_CONFIG

All changes will be logged to:
  $LOG_FILE"
    
    tui_msgbox "SFM Setup Wizard" "$welcome_msg"
}

# Main execution
main() {
    log "=== SFM Setup Started ==="
    log "User: $USER, Shell: $SHELL"
    
    # Setup TUI
    setup_tui
    
    # Detect shell
    detect_shell
    
    # Initialize files
    init_files
    
    # Show welcome
    show_welcome
    
    # Show main menu
    show_main_menu
    
    log "=== SFM Setup Completed ==="
}

# Error handler
error_handler() {
    local line=$1
    log "ERROR: Script failed at line $line"
    echo ""
    echo -e "${RED}Error occurred at line $line${NC}"
    echo -e "${YELLOW}Check log file: $LOG_FILE${NC}"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main
main