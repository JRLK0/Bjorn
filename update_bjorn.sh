#!/bin/bash

# BJORN Update Script
# This script updates an existing BJORN installation
# Author: infinition
# Version: 1.0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging configuration
LOG_DIR="/var/log/bjorn_update"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bjorn_update_$(date +%Y%m%d_%H%M%S).log"
VERBOSE=false

# Global variables
BJORN_USER="bjorn"
BJORN_PATH="/home/${BJORN_USER}/Bjorn"
CURRENT_STEP=0
TOTAL_STEPS=7

if [[ "$1" == "--help" ]]; then
    echo "Usage: sudo ./update_bjorn.sh"
    echo "This script updates an existing BJORN installation."
    echo "It will:"
    echo "  - Backup current configuration"
    echo "  - Update code from repository"
    echo "  - Install new dependencies"
    echo "  - Update configuration files"
    echo "  - Restart BJORN service"
    exit 0
fi

# Function to display progress
show_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${BLUE}Step $CURRENT_STEP of $TOTAL_STEPS: $1${NC}"
}

# Logging function
log() {
    local level=$1
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "$message" >> "$LOG_FILE"
    if [ "$VERBOSE" = true ] || [ "$level" != "DEBUG" ]; then
        case $level in
            "ERROR") echo -e "${RED}$message${NC}" ;;
            "SUCCESS") echo -e "${GREEN}$message${NC}" ;;
            "WARNING") echo -e "${YELLOW}$message${NC}" ;;
            "INFO") echo -e "${BLUE}$message${NC}" ;;
            *) echo -e "$message" ;;
        esac
    fi
}

# Error handling function
handle_error() {
    local error_code=$?
    local error_message=$1
    log "ERROR" "An error occurred during: $error_message (Error code: $error_code)"
    log "ERROR" "Check the log file for details: $LOG_FILE"
    echo -e "${RED}Error: $error_message${NC}"
    echo -e "${YELLOW}Check the log file: $LOG_FILE${NC}"
    return 1
}

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        log "SUCCESS" "$1"
        return 0
    else
        handle_error "$1"
        return $?
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Check if BJORN is installed
check_bjorn_installed() {
    log "INFO" "Checking if BJORN is installed..."
    
    if [ ! -d "$BJORN_PATH" ]; then
        log "ERROR" "BJORN directory not found at $BJORN_PATH"
        echo -e "${RED}BJORN is not installed at $BJORN_PATH${NC}"
        echo -e "${YELLOW}Please run install_bjorn.sh first${NC}"
        exit 1
    fi
    
    if [ ! -f "$BJORN_PATH/Bjorn.py" ]; then
        log "ERROR" "BJORN.py not found. Installation may be corrupted."
        exit 1
    fi
    
    check_success "BJORN installation found"
}

# Backup current configuration
backup_configuration() {
    log "INFO" "Backing up current configuration..."
    
    BACKUP_DIR="/home/${BJORN_USER}/Bjorn_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup configuration files
    if [ -d "$BJORN_PATH/config" ]; then
        cp -r "$BJORN_PATH/config" "$BACKUP_DIR/" 2>/dev/null
        log "INFO" "Backed up configuration directory"
    fi
    
    # Backup data directory (optional, can be large)
    echo -e "${YELLOW}Do you want to backup the data directory? (y/n)${NC}"
    read -r backup_data
    if [[ "$backup_data" =~ ^[Yy]$ ]]; then
        if [ -d "$BJORN_PATH/data" ]; then
            cp -r "$BJORN_PATH/data" "$BACKUP_DIR/" 2>/dev/null
            log "INFO" "Backed up data directory"
        fi
    fi
    
    log "SUCCESS" "Configuration backed up to $BACKUP_DIR"
    echo -e "${GREEN}Backup created at: $BACKUP_DIR${NC}"
}

# Update code from repository
update_code() {
    log "INFO" "Updating BJORN code..."
    
    cd "$BJORN_PATH" || exit 1
    
    # Check if it's a git repository
    if [ -d ".git" ]; then
        log "INFO" "Detected git repository, checking remote..."
        
        # Get the remote URL
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        
        if [ -z "$REMOTE_URL" ]; then
            log "WARNING" "No remote repository configured. Setting default remote..."
            git remote add origin https://github.com/infinition/Bjorn.git 2>/dev/null || \
            git remote set-url origin https://github.com/infinition/Bjorn.git
            REMOTE_URL="https://github.com/infinition/Bjorn.git"
        fi
        
        log "INFO" "Updating from repository: $REMOTE_URL"
        
        # Fetch latest changes
        git fetch origin
        if [ $? -ne 0 ]; then
            log "WARNING" "Failed to fetch from origin, trying to set remote..."
            git remote set-url origin https://github.com/infinition/Bjorn.git
            git fetch origin
        fi
        
        # Get current branch
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
        log "INFO" "Current branch: $CURRENT_BRANCH"
        
        # Pull latest changes
        git pull origin "$CURRENT_BRANCH" || git pull origin main || git pull origin master
        check_success "Code updated from git repository ($REMOTE_URL)"
    else
        log "WARNING" "Not a git repository. This installation was not cloned from git."
        log "INFO" "To enable automatic updates, consider cloning from: https://github.com/infinition/Bjorn.git"
        echo -e "${YELLOW}This installation is not a git repository.${NC}"
        echo -e "${YELLOW}Automatic code update skipped.${NC}"
        echo -e "${YELLOW}To enable updates, reinstall using: git clone https://github.com/infinition/Bjorn.git${NC}"
        return 0
    fi
}

# Install new dependencies
install_dependencies() {
    log "INFO" "Checking and installing new dependencies..."
    
    # Check if aircrack-ng is installed (required for WiFi handshake capture)
    if ! command -v airodump-ng &> /dev/null; then
        log "INFO" "Installing aircrack-ng for WiFi handshake capture..."
        apt-get update
        apt-get install -y aircrack-ng
        check_success "Installed aircrack-ng"
    else
        log "INFO" "aircrack-ng is already installed"
    fi
    
    # Update Python requirements
    cd "$BJORN_PATH" || exit 1
    if [ -f "requirements.txt" ]; then
        log "INFO" "Updating Python requirements..."
        pip3 install -r requirements.txt --break-system-packages --upgrade
        check_success "Updated Python requirements"
    fi
}

# Update configuration files
update_configuration() {
    log "INFO" "Updating configuration files..."
    
    cd "$BJORN_PATH" || exit 1
    
    # Check if shared_config.json exists
    if [ -f "config/shared_config.json" ]; then
        # Backup current config
        cp "config/shared_config.json" "config/shared_config.json.backup"
        
        # Load current config and merge with defaults
        log "INFO" "Merging new configuration options..."
        
        # Use Python to merge configs (more reliable than sed)
        python3 << EOF
import json
import os

config_file = "config/shared_config.json"
backup_file = "config/shared_config.json.backup"

# Load current config
with open(backup_file, 'r') as f:
    current_config = json.load(f)

# Default new options for WiFi handshake capture
new_options = {
    "__title_wifi_handshake__": "WiFi Handshake Capture",
    "wifi_handshake_enabled": True,
    "wifi_handshake_interval": 300,
    "wifi_handshake_duration": 60,
    "wifi_handshake_scan_duration": 10,
    "wifi_interface": "wlan0"
}

# Merge: keep existing values, add new ones
for key, value in new_options.items():
    if key not in current_config:
        current_config[key] = value
        print(f"Added new config option: {key} = {value}")

# Save updated config
with open(config_file, 'w') as f:
    json.dump(current_config, f, indent=4)

print("Configuration updated successfully")
EOF
        
        check_success "Configuration updated"
    else
        log "WARNING" "Configuration file not found, it will be created on first run"
    fi
}

# Regenerate actions.json
regenerate_actions() {
    log "INFO" "Regenerating actions.json..."
    
    cd "$BJORN_PATH" || exit 1
    
    # Run Python to regenerate actions.json
    sudo -u $BJORN_USER python3 << EOF
import sys
sys.path.insert(0, '/home/bjorn/Bjorn')
from shared import SharedData

try:
    shared_data = SharedData()
    shared_data.generate_actions_json()
    print("Actions.json regenerated successfully")
except Exception as e:
    print(f"Error regenerating actions.json: {e}")
    sys.exit(1)
EOF
    
    check_success "Actions.json regenerated"
}

# Restart BJORN service
restart_service() {
    log "INFO" "Restarting BJORN service..."
    
    if systemctl is-active --quiet bjorn.service; then
        systemctl restart bjorn.service
        sleep 2
        
        if systemctl is-active --quiet bjorn.service; then
            log "SUCCESS" "BJORN service restarted successfully"
            echo -e "${GREEN}BJORN service restarted${NC}"
        else
            log "ERROR" "BJORN service failed to start"
            echo -e "${RED}BJORN service failed to start. Check logs with: sudo journalctl -u bjorn.service${NC}"
            systemctl status bjorn.service
        fi
    else
        log "WARNING" "BJORN service is not running"
        echo -e "${YELLOW}BJORN service is not running. Start it with: sudo systemctl start bjorn.service${NC}"
    fi
}

# Verify update
verify_update() {
    log "INFO" "Verifying update..."
    
    # Check if new files exist
    if [ -f "$BJORN_PATH/actions/wifi_handshake_capture.py" ]; then
        log "SUCCESS" "New WiFi handshake capture module found"
    else
        log "WARNING" "WiFi handshake capture module not found"
    fi
    
    # Check if handshakes directory path exists in shared.py
    if grep -q "handshakes_dir" "$BJORN_PATH/shared.py"; then
        log "SUCCESS" "Handshakes directory configuration found"
    else
        log "WARNING" "Handshakes directory configuration not found"
    fi
    
    # Check Python syntax
    cd "$BJORN_PATH" || exit 1
    if python3 -m py_compile Bjorn.py 2>/dev/null; then
        log "SUCCESS" "Python syntax check passed"
    else
        log "WARNING" "Python syntax check failed"
    fi
    
    echo -e "${GREEN}Update verification completed${NC}"
}

# Main update process
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   BJORN Update Script${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    log "INFO" "Starting BJORN update process..."
    
    # Check root
    check_root
    
    # Check if BJORN is installed
    show_progress "Checking BJORN installation"
    check_bjorn_installed || exit 1
    
    # Backup configuration
    show_progress "Backing up configuration"
    backup_configuration || exit 1
    
    # Update code
    show_progress "Updating code from repository"
    update_code || exit 1
    
    # Install dependencies
    show_progress "Installing new dependencies"
    install_dependencies || exit 1
    
    # Update configuration
    show_progress "Updating configuration files"
    update_configuration || exit 1
    
    # Regenerate actions
    show_progress "Regenerating actions.json"
    regenerate_actions || exit 1
    
    # Restart service
    show_progress "Restarting BJORN service"
    restart_service || exit 1
    
    # Verify update
    show_progress "Verifying update"
    verify_update || exit 1
    
    log "SUCCESS" "BJORN update completed successfully!"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   Update Completed Successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}New features:${NC}"
    echo -e "  - WiFi Handshake Capture (when not connected to WiFi)"
    echo ""
    echo -e "${YELLOW}Note:${NC}"
    echo -e "  - Configuration has been backed up"
    echo -e "  - New WiFi handshake options added to config"
    echo -e "  - Check logs at: $LOG_FILE"
    echo ""
}

# Run main function
main

