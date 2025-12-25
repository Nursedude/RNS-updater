#!/bin/bash

#########################################################
# Reticulum Ecosystem Update Installer
# For Raspberry Pi OS
# Updates: RNS, LXMF, Nomad Network, and MeshChat
#########################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Global variables
BACKUP_DIR="$HOME/.reticulum_backup_$(date +%Y%m%d_%H%M%S)"
UPDATE_LOG="$HOME/reticulum_update_$(date +%Y%m%d_%H%M%S).log"
MESHCHAT_DIR="$HOME/reticulum-meshchat"

#########################################################
# Helper Functions
#########################################################

print_header() {
    echo -e "\n${CYAN}${BOLD}============================================${NC}"
    echo -e "${CYAN}${BOLD}  Reticulum Ecosystem Update Installer${NC}"
    echo -e "${CYAN}${BOLD}============================================${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}${BOLD}>>> $1${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$UPDATE_LOG"
}

pause_for_input() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

#########################################################
# Check Functions
#########################################################

check_python() {
    print_section "Checking Python Installation"
    
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        print_success "Python3 found: $PYTHON_VERSION"
        log_message "Python3 version: $PYTHON_VERSION"
        return 0
    else
        print_error "Python3 not found!"
        return 1
    fi
}

check_pip() {
    print_section "Checking pip Installation"
    
    if command -v pip3 &> /dev/null || command -v pip &> /dev/null; then
        if command -v pip3 &> /dev/null; then
            PIP_CMD="pip3"
        else
            PIP_CMD="pip"
        fi
        PIP_VERSION=$($PIP_CMD --version 2>&1 | awk '{print $2}')
        print_success "pip found: $PIP_VERSION"
        log_message "pip version: $PIP_VERSION"
        return 0
    else
        print_error "pip not found!"
        return 1
    fi
}

get_installed_version() {
    local package=$1
    $PIP_CMD show "$package" 2>/dev/null | grep "^Version:" | awk '{print $2}'
}

check_package_installed() {
    local package=$1
    local display_name=$2
    
    VERSION=$(get_installed_version "$package")
    
    if [ -n "$VERSION" ]; then
        print_info "$display_name is installed: version $VERSION"
        log_message "$display_name installed: $VERSION"
        echo "$VERSION"
        return 0
    else
        print_warning "$display_name is not installed"
        log_message "$display_name not installed"
        echo ""
        return 1
    fi
}

check_meshchat_installed() {
    print_section "Checking MeshChat Installation"
    
    if [ -d "$MESHCHAT_DIR" ]; then
        if [ -f "$MESHCHAT_DIR/package.json" ]; then
            MESHCHAT_VERSION=$(grep '"version"' "$MESHCHAT_DIR/package.json" | head -1 | awk -F'"' '{print $4}')
            print_info "MeshChat found: version $MESHCHAT_VERSION"
            log_message "MeshChat installed: $MESHCHAT_VERSION"
            return 0
        else
            print_warning "MeshChat directory found but package.json missing"
            log_message "MeshChat directory exists but corrupted"
            return 1
        fi
    else
        print_warning "MeshChat is not installed at $MESHCHAT_DIR"
        log_message "MeshChat not installed"
        return 1
    fi
}

#########################################################
# Backup Functions
#########################################################

create_backup() {
    print_section "Creating Backup"
    
    echo -e "${YELLOW}Do you want to create a backup before updating? (recommended)${NC}"
    echo -e "Backup will include configuration files from:"
    echo "  - ~/.reticulum/"
    echo "  - ~/.nomadnetwork/"
    echo "  - ~/.lxmf/"
    echo -n "Create backup? (Y/n): "
    read -r BACKUP_CHOICE
    
    if [[ "$BACKUP_CHOICE" =~ ^[Nn]$ ]]; then
        print_warning "Skipping backup (not recommended)"
        log_message "User skipped backup"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup RNS config
    if [ -d "$HOME/.reticulum" ]; then
        cp -r "$HOME/.reticulum" "$BACKUP_DIR/" 2>/dev/null
        print_success "Backed up Reticulum config"
        log_message "Backed up ~/.reticulum"
    fi
    
    # Backup Nomad Network config
    if [ -d "$HOME/.nomadnetwork" ]; then
        cp -r "$HOME/.nomadnetwork" "$BACKUP_DIR/" 2>/dev/null
        print_success "Backed up Nomad Network config"
        log_message "Backed up ~/.nomadnetwork"
    fi
    
    # Backup LXMF config
    if [ -d "$HOME/.lxmf" ]; then
        cp -r "$HOME/.lxmf" "$BACKUP_DIR/" 2>/dev/null
        print_success "Backed up LXMF config"
        log_message "Backed up ~/.lxmf"
    fi
    
    print_success "Backup created at: $BACKUP_DIR"
    log_message "Backup created at: $BACKUP_DIR"
}

#########################################################
# Update Functions
#########################################################

stop_services() {
    print_section "Stopping Running Services"
    
    # Stop rnsd if running
    if pgrep -f "rnsd" > /dev/null; then
        print_info "Stopping rnsd daemon..."
        rnsd --daemon stop 2>/dev/null || killall rnsd 2>/dev/null
        sleep 2
        print_success "rnsd stopped"
        log_message "Stopped rnsd daemon"
    fi
    
    # Check for nomadnet processes
    if pgrep -f "nomadnet" > /dev/null; then
        print_warning "Nomad Network appears to be running. Please close it manually."
        echo -n "Press Enter when Nomad Network is closed..."
        read
        log_message "User closed Nomad Network manually"
    fi
    
    # Check for MeshChat processes
    if pgrep -f "meshchat" > /dev/null || pgrep -f "electron" > /dev/null; then
        print_warning "MeshChat/Electron appears to be running. Please close it manually."
        echo -n "Press Enter when MeshChat is closed..."
        read
        log_message "User closed MeshChat manually"
    fi
}

update_pip_package() {
    local package=$1
    local display_name=$2
    
    print_section "Updating $display_name"
    
    OLD_VERSION=$(get_installed_version "$package")
    
    if [ -z "$OLD_VERSION" ]; then
        print_info "Installing $display_name (not currently installed)..."
        log_message "Installing $display_name"
    else
        print_info "Current version: $OLD_VERSION"
        print_info "Updating to latest version..."
        log_message "Updating $display_name from $OLD_VERSION"
    fi
    
    # Try update with --break-system-packages flag (needed on newer Raspberry Pi OS)
    if $PIP_CMD install "$package" --upgrade --break-system-packages 2>&1 | tee -a "$UPDATE_LOG"; then
        NEW_VERSION=$(get_installed_version "$package")
        
        if [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
            print_success "$display_name updated: $OLD_VERSION → $NEW_VERSION"
            log_message "$display_name updated to $NEW_VERSION"
        else
            print_success "$display_name is already at the latest version: $NEW_VERSION"
            log_message "$display_name already latest: $NEW_VERSION"
        fi
        return 0
    else
        print_error "Failed to update $display_name"
        log_message "Failed to update $display_name"
        return 1
    fi
}

update_meshchat() {
    print_section "Updating MeshChat"
    
    if ! check_meshchat_installed; then
        echo -e "\n${YELLOW}MeshChat is not installed. Would you like to install it?${NC}"
        echo -n "Install MeshChat? (y/N): "
        read -r INSTALL_MESHCHAT
        
        if [[ "$INSTALL_MESHCHAT" =~ ^[Yy]$ ]]; then
            install_meshchat
        else
            print_warning "Skipping MeshChat installation"
            log_message "User skipped MeshChat installation"
        fi
        return 0
    fi
    
    # Check for required tools
    if ! command -v git &> /dev/null; then
        print_error "git is required but not installed"
        echo -n "Install git? (Y/n): "
        read -r INSTALL_GIT
        if [[ ! "$INSTALL_GIT" =~ ^[Nn]$ ]]; then
            sudo apt update
            sudo apt install -y git
        else
            print_warning "Skipping MeshChat update (git required)"
            return 1
        fi
    fi
    
    if ! command -v npm &> /dev/null; then
        print_error "npm is required but not installed"
        echo -n "Install Node.js and npm? (Y/n): "
        read -r INSTALL_NPM
        if [[ ! "$INSTALL_NPM" =~ ^[Nn]$ ]]; then
            sudo apt update
            sudo apt install -y nodejs npm
        else
            print_warning "Skipping MeshChat update (npm required)"
            return 1
        fi
    fi
    
    cd "$MESHCHAT_DIR" || return 1
    
    print_info "Fetching latest MeshChat updates..."
    log_message "Updating MeshChat from git"
    
    if git pull origin main 2>&1 | tee -a "$UPDATE_LOG"; then
        print_success "MeshChat source updated"
        
        print_info "Installing/updating dependencies..."
        if npm install 2>&1 | tee -a "$UPDATE_LOG"; then
            print_success "Dependencies updated"
            
            print_info "Building MeshChat..."
            if npm run build 2>&1 | tee -a "$UPDATE_LOG"; then
                NEW_MESHCHAT_VERSION=$(grep '"version"' package.json | head -1 | awk -F'"' '{print $4}')
                print_success "MeshChat updated to version $NEW_MESHCHAT_VERSION"
                log_message "MeshChat updated to $NEW_MESHCHAT_VERSION"
            else
                print_error "Failed to build MeshChat"
                log_message "MeshChat build failed"
                return 1
            fi
        else
            print_error "Failed to install dependencies"
            log_message "MeshChat npm install failed"
            return 1
        fi
    else
        print_error "Failed to update MeshChat source"
        log_message "MeshChat git pull failed"
        return 1
    fi
    
    cd - > /dev/null
}

install_meshchat() {
    print_section "Installing MeshChat"
    
    # Check for required tools
    if ! command -v git &> /dev/null; then
        print_info "Installing git..."
        sudo apt update
        sudo apt install -y git
    fi
    
    if ! command -v npm &> /dev/null; then
        print_info "Installing Node.js and npm..."
        sudo apt update
        sudo apt install -y nodejs npm
    fi
    
    print_info "Cloning MeshChat repository..."
    log_message "Installing MeshChat"
    
    if git clone https://github.com/liamcottle/reticulum-meshchat.git "$MESHCHAT_DIR" 2>&1 | tee -a "$UPDATE_LOG"; then
        cd "$MESHCHAT_DIR" || return 1
        
        print_info "Installing dependencies..."
        if npm install 2>&1 | tee -a "$UPDATE_LOG"; then
            print_info "Building MeshChat..."
            if npm run build 2>&1 | tee -a "$UPDATE_LOG"; then
                MESHCHAT_VERSION=$(grep '"version"' package.json | head -1 | awk -F'"' '{print $4}')
                print_success "MeshChat installed: version $MESHCHAT_VERSION"
                log_message "MeshChat installed: $MESHCHAT_VERSION"
                
                # Create desktop launcher if on Raspberry Pi Desktop
                create_meshchat_launcher
            else
                print_error "Failed to build MeshChat"
                log_message "MeshChat build failed"
                return 1
            fi
        else
            print_error "Failed to install dependencies"
            log_message "MeshChat npm install failed"
            return 1
        fi
        
        cd - > /dev/null
    else
        print_error "Failed to clone MeshChat repository"
        log_message "MeshChat git clone failed"
        return 1
    fi
}

create_meshchat_launcher() {
    if [ -n "$DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        print_info "Creating desktop launcher..."
        
        DESKTOP_FILE="$HOME/.local/share/applications/meshchat.desktop"
        mkdir -p "$HOME/.local/share/applications"
        
        cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Reticulum MeshChat
Comment=LXMF client for Reticulum
Exec=bash -c 'cd $MESHCHAT_DIR && npm run dev'
Icon=$MESHCHAT_DIR/icon.png
Terminal=false
Categories=Network;Communication;
EOF
        
        chmod +x "$DESKTOP_FILE"
        print_success "Desktop launcher created"
        log_message "Created desktop launcher"
    fi
}

start_services() {
    print_section "Starting Services"
    
    echo -e "${YELLOW}Do you want to start rnsd daemon now?${NC}"
    echo -n "Start rnsd? (Y/n): "
    read -r START_RNSD
    
    if [[ ! "$START_RNSD" =~ ^[Nn]$ ]]; then
        print_info "Starting rnsd daemon..."
        if rnsd --daemon 2>&1 | tee -a "$UPDATE_LOG"; then
            sleep 2
            print_success "rnsd daemon started"
            log_message "Started rnsd daemon"
        else
            print_error "Failed to start rnsd daemon"
            log_message "Failed to start rnsd daemon"
        fi
    fi
}

#########################################################
# Display Functions
#########################################################

show_summary() {
    print_section "Update Summary"
    
    echo -e "${BOLD}Updated Components:${NC}"
    
    RNS_VER=$(get_installed_version "rns")
    [ -n "$RNS_VER" ] && echo -e "  ${GREEN}✓${NC} RNS (Reticulum): $RNS_VER"
    
    LXMF_VER=$(get_installed_version "lxmf")
    [ -n "$LXMF_VER" ] && echo -e "  ${GREEN}✓${NC} LXMF: $LXMF_VER"
    
    NOMAD_VER=$(get_installed_version "nomadnet")
    [ -n "$NOMAD_VER" ] && echo -e "  ${GREEN}✓${NC} Nomad Network: $NOMAD_VER"
    
    if [ -d "$MESHCHAT_DIR" ] && [ -f "$MESHCHAT_DIR/package.json" ]; then
        MESHCHAT_VER=$(grep '"version"' "$MESHCHAT_DIR/package.json" | head -1 | awk -F'"' '{print $4}')
        echo -e "  ${GREEN}✓${NC} MeshChat: $MESHCHAT_VER"
    fi
    
    echo ""
    print_info "Update log saved to: $UPDATE_LOG"
    
    if [ -d "$BACKUP_DIR" ]; then
        print_info "Backup saved to: $BACKUP_DIR"
    fi
    
    echo ""
    echo -e "${CYAN}${BOLD}Next Steps:${NC}"
    echo -e "  1. Test your installation by running: ${YELLOW}rnstatus${NC}"
    echo -e "  2. Launch Nomad Network: ${YELLOW}nomadnet${NC}"
    
    if [ -d "$MESHCHAT_DIR" ]; then
        echo -e "  3. Launch MeshChat: ${YELLOW}cd $MESHCHAT_DIR && npm run dev${NC}"
    fi
    
    echo ""
}

#########################################################
# Main Update Logic
#########################################################

main() {
    print_header
    
    log_message "=== Reticulum Update Started ==="
    
    # Check prerequisites
    if ! check_python; then
        print_error "Python3 is required. Install it with: sudo apt install python3"
        exit 1
    fi
    
    if ! check_pip; then
        print_error "pip is required. Install it with: sudo apt install python3-pip"
        exit 1
    fi
    
    # Check what's currently installed
    print_section "Checking Installed Components"
    
    RNS_INSTALLED=$(check_package_installed "rns" "RNS (Reticulum)")
    LXMF_INSTALLED=$(check_package_installed "lxmf" "LXMF")
    NOMAD_INSTALLED=$(check_package_installed "nomadnet" "Nomad Network")
    MESHCHAT_INSTALLED=false
    check_meshchat_installed && MESHCHAT_INSTALLED=true
    
    if [ -z "$RNS_INSTALLED" ] && [ -z "$LXMF_INSTALLED" ] && [ -z "$NOMAD_INSTALLED" ] && [ "$MESHCHAT_INSTALLED" = false ]; then
        print_warning "No Reticulum components appear to be installed!"
        echo -e "\n${YELLOW}Would you like to perform a fresh installation instead?${NC}"
        echo -n "Fresh install? (y/N): "
        read -r FRESH_INSTALL
        
        if [[ "$FRESH_INSTALL" =~ ^[Yy]$ ]]; then
            print_info "Performing fresh installation..."
            update_pip_package "rns" "RNS (Reticulum)"
            update_pip_package "lxmf" "LXMF"
            update_pip_package "nomadnet" "Nomad Network"
            
            echo -e "\n${YELLOW}Install MeshChat as well?${NC}"
            echo -n "Install MeshChat? (y/N): "
            read -r INSTALL_MC
            [[ "$INSTALL_MC" =~ ^[Yy]$ ]] && install_meshchat
            
            start_services
            show_summary
            exit 0
        else
            print_warning "No components to update. Exiting."
            exit 0
        fi
    fi
    
    # Create backup
    create_backup
    pause_for_input
    
    # Stop running services
    stop_services
    pause_for_input
    
    # Update components
    echo -e "\n${CYAN}${BOLD}Starting Update Process...${NC}\n"
    
    # Always update RNS first (other components depend on it)
    if [ -n "$RNS_INSTALLED" ] || [ -n "$LXMF_INSTALLED" ] || [ -n "$NOMAD_INSTALLED" ]; then
        update_pip_package "rns" "RNS (Reticulum)"
        sleep 1
    fi
    
    # Update LXMF (required for Nomad Network and MeshChat)
    if [ -n "$LXMF_INSTALLED" ] || [ -n "$NOMAD_INSTALLED" ] || [ "$MESHCHAT_INSTALLED" = true ]; then
        update_pip_package "lxmf" "LXMF"
        sleep 1
    fi
    
    # Update Nomad Network
    if [ -n "$NOMAD_INSTALLED" ]; then
        update_pip_package "nomadnet" "Nomad Network"
        sleep 1
    fi
    
    # Update MeshChat
    if [ "$MESHCHAT_INSTALLED" = true ]; then
        update_meshchat
        sleep 1
    else
        echo -e "\n${YELLOW}MeshChat is not installed. Would you like to install it?${NC}"
        echo -n "Install MeshChat? (y/N): "
        read -r INSTALL_MC
        
        if [[ "$INSTALL_MC" =~ ^[Yy]$ ]]; then
            install_meshchat
        fi
    fi
    
    # Start services
    start_services
    
    # Show summary
    show_summary
    
    log_message "=== Reticulum Update Completed ==="
    
    print_success "\nUpdate process completed!"
}

#########################################################
# Script Entry Point
#########################################################

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && ! grep -q "BCM" /proc/cpuinfo 2>/dev/null; then
    print_warning "This script is designed for Raspberry Pi but can work on other Debian-based systems."
    echo -n "Continue anyway? (y/N): "
    read -r CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Exiting."
        exit 0
    fi
fi

# Run main function
main

exit 0
