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
DEFAULT_REPO="https://github.com/JRLK0/Bjorn.git"
CURRENT_STEP=0
TOTAL_STEPS=8

if [[ "$1" == "--help" ]]; then
    echo "Usage: sudo ./update_bjorn.sh [REPOSITORY_URL]"
    echo "This script updates an existing BJORN installation."
    echo ""
    echo "Options:"
    echo "  REPOSITORY_URL    Optional. Git repository URL to update from."
    echo "                    Default: $DEFAULT_REPO"
    echo ""
    echo "It will:"
    echo "  - Backup current configuration"
    echo "  - Update code from repository"
    echo "  - Install new dependencies"
    echo "  - Update configuration files"
    echo "  - Restart BJORN service"
    exit 0
fi

# Allow custom repository URL as argument
if [ -n "$1" ] && [[ "$1" != "--help" ]]; then
    DEFAULT_REPO="$1"
    log "INFO" "Using custom repository: $DEFAULT_REPO"
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
    
    # First, detect the branch and remote from the directory where script is being executed
    # This allows testing from any directory and uses the correct fork
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SCRIPT_BRANCH=""
    SCRIPT_REMOTE=""
    
    # Check if script is in a git repo (for testing/development)
    if [ -d "$SCRIPT_DIR/.git" ]; then
        cd "$SCRIPT_DIR" || exit 1
        log "INFO" "Script is in a git repository, detecting branch and remote from script location..."
        SCRIPT_BRANCH=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
        SCRIPT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
        log "INFO" "Detected branch from script location: ${SCRIPT_BRANCH:-unknown}"
        log "INFO" "Detected remote from script location: ${SCRIPT_REMOTE:-unknown}"
    fi
    
    # Now go to the actual BJORN installation directory
    cd "$BJORN_PATH" || exit 1
    
    # Check if it's a git repository
    if [ -d ".git" ]; then
        log "INFO" "Detected git repository, checking remote..."
        
        # Get the remote URL from installation
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
        
        # If script has a remote and it's different, use the script's remote (the fork)
        if [ -n "$SCRIPT_REMOTE" ] && [ "$SCRIPT_REMOTE" != "$REMOTE_URL" ]; then
            log "INFO" "Script remote ($SCRIPT_REMOTE) differs from installation remote ($REMOTE_URL)"
            log "INFO" "Updating installation remote to match script remote (your fork)..."
            git remote set-url origin "$SCRIPT_REMOTE"
            REMOTE_URL="$SCRIPT_REMOTE"
        elif [ -z "$REMOTE_URL" ]; then
            log "WARNING" "No remote repository configured. Setting default remote..."
            git remote add origin "$DEFAULT_REPO" 2>/dev/null || \
            git remote set-url origin "$DEFAULT_REPO"
            REMOTE_URL="$DEFAULT_REPO"
        fi
        
        log "INFO" "Updating from repository: $REMOTE_URL"
        
        # Fetch latest changes
        git fetch origin
        if [ $? -ne 0 ]; then
            log "WARNING" "Failed to fetch from origin, trying to set remote..."
            if [ -n "$SCRIPT_REMOTE" ]; then
                git remote set-url origin "$SCRIPT_REMOTE"
            else
                git remote set-url origin "$DEFAULT_REPO"
            fi
            git fetch origin
        fi
        
        # Get current branch from the installation directory
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
        
        if [ -z "$CURRENT_BRANCH" ]; then
            # Try alternative method to get branch name
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        fi
        
        # If we detected a branch from script location and it's different, use that
        if [ -n "$SCRIPT_BRANCH" ] && [ "$SCRIPT_BRANCH" != "$CURRENT_BRANCH" ]; then
            log "INFO" "Script is in branch '$SCRIPT_BRANCH', switching installation to that branch..."
            # Checkout the branch from script location
            git checkout "$SCRIPT_BRANCH" 2>/dev/null || {
                log "INFO" "Branch $SCRIPT_BRANCH doesn't exist locally, creating tracking branch..."
                git checkout -b "$SCRIPT_BRANCH" "origin/$SCRIPT_BRANCH" 2>/dev/null || {
                    log "WARNING" "Could not switch to branch $SCRIPT_BRANCH, using current branch"
                }
            }
            CURRENT_BRANCH="$SCRIPT_BRANCH"
        fi
        
        if [ -z "$CURRENT_BRANCH" ]; then
            log "WARNING" "Could not detect current branch, trying default branches..."
            # Try common branch names
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
                log "ERROR" "Failed to pull from repository. Please check your branch and remote configuration."
                return 1
            }
        else
            log "INFO" "Using branch: $CURRENT_BRANCH"
            log "INFO" "Updating from branch: $CURRENT_BRANCH"
            
            # Pull latest changes from the current branch
            git pull origin "$CURRENT_BRANCH"
            if [ $? -ne 0 ]; then
                log "WARNING" "Failed to pull from branch $CURRENT_BRANCH, trying to set upstream..."
                # Set upstream if not set
                git branch --set-upstream-to=origin/"$CURRENT_BRANCH" "$CURRENT_BRANCH" 2>/dev/null
                git pull origin "$CURRENT_BRANCH"
            fi
        fi
        
        check_success "Code updated from git repository ($REMOTE_URL, branch: ${CURRENT_BRANCH:-unknown})"
    else
        log "WARNING" "Not a git repository. This installation was not cloned from git."
        log "INFO" "To enable automatic updates, consider cloning from: $DEFAULT_REPO"
        echo -e "${YELLOW}This installation is not a git repository.${NC}"
        echo -e "${YELLOW}Automatic code update skipped.${NC}"
        echo -e "${YELLOW}To enable updates, reinstall using: git clone $DEFAULT_REPO${NC}"
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
    
    # Fix permissions on config directory first
    chown -R $BJORN_USER:$BJORN_USER "$BJORN_PATH/config" 2>/dev/null || true
    chmod -R 755 "$BJORN_PATH/config" 2>/dev/null || true
    
    # Check if shared_config.json exists
    if [ -f "config/shared_config.json" ]; then
        # Backup current config
        cp "config/shared_config.json" "config/shared_config.json.backup"
        chown $BJORN_USER:$BJORN_USER "config/shared_config.json.backup" 2>/dev/null || true
        
        # Load current config and merge with defaults
        log "INFO" "Merging new configuration options..."
        
        # Use Python to merge configs (more reliable than sed) as bjorn user
        sudo -u $BJORN_USER python3 << 'PYEOF'
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
PYEOF
        
        # Fix permissions on updated config
        chown $BJORN_USER:$BJORN_USER "config/shared_config.json" 2>/dev/null || true
        chmod 644 "config/shared_config.json" 2>/dev/null || true
        
        check_success "Configuration updated"
    else
        log "WARNING" "Configuration file not found, it will be created on first run"
    fi
}

# Regenerate actions.json
regenerate_actions() {
    log "INFO" "Regenerating actions.json..."
    
    cd "$BJORN_PATH" || exit 1
    
    # Fix permissions on config and data directories
    chown -R $BJORN_USER:$BJORN_USER "$BJORN_PATH/config" 2>/dev/null || true
    chown -R $BJORN_USER:$BJORN_USER "$BJORN_PATH/data" 2>/dev/null || true
    chmod -R 755 "$BJORN_PATH/config" 2>/dev/null || true
    chmod -R 755 "$BJORN_PATH/data" 2>/dev/null || true
    
    # Run Python to regenerate actions.json as bjorn user
    # Use a minimal script that doesn't initialize EPD display
    sudo -u $BJORN_USER bash -c "cd '$BJORN_PATH' && python3 << 'PYEOF'
import sys
import os
import json
import importlib

# Add path
sys.path.insert(0, '$BJORN_PATH')

try:
    # Get actions directory
    actions_dir = os.path.join('$BJORN_PATH', 'actions')
    actions_file = os.path.join('$BJORN_PATH', 'config', 'actions.json')
    
    # Ensure config directory exists
    os.makedirs(os.path.dirname(actions_file), exist_ok=True)
    
    actions_config = []
    
    # Scan actions directory
    for filename in os.listdir(actions_dir):
        if filename.endswith('.py') and filename != '__init__.py':
            module_name = filename[:-3]
            try:
                module = importlib.import_module(f'actions.{module_name}')
                b_class = getattr(module, 'b_class', None)
                b_status = getattr(module, 'b_status', None)
                b_port = getattr(module, 'b_port', None)
                b_parent = getattr(module, 'b_parent', None)
                
                if b_class and b_status is not None:
                    actions_config.append({
                        'b_module': module_name,
                        'b_class': b_class,
                        'b_port': b_port,
                        'b_status': b_status,
                        'b_parent': b_parent
                    })
            except AttributeError as e:
                print(f'Warning: Module {module_name} missing attributes: {e}')
            except ImportError as e:
                print(f'Warning: Error importing {module_name}: {e}')
            except Exception as e:
                print(f'Warning: Error processing {module_name}: {e}')
    
    # Write actions.json
    with open(actions_file, 'w') as f:
        json.dump(actions_config, f, indent=4)
    
    print(f'Actions.json regenerated successfully with {len(actions_config)} actions')
    
except Exception as e:
    print(f'Error regenerating actions.json: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF"
    
    # Fix permissions on generated file
    chown $BJORN_USER:$BJORN_USER "$BJORN_PATH/config/actions.json" 2>/dev/null || true
    chmod 644 "$BJORN_PATH/config/actions.json" 2>/dev/null || true
    
    check_success "Actions.json regenerated"
}

# Fix script permissions
fix_script_permissions() {
    log "INFO" "Fixing script permissions..."
    
    cd "$BJORN_PATH" || exit 1
    
    # Fix permissions on executable scripts
    if [ -f "kill_port_8000.sh" ]; then
        chmod +x "kill_port_8000.sh"
        chown $BJORN_USER:$BJORN_USER "kill_port_8000.sh" 2>/dev/null || true
        log "INFO" "Fixed permissions on kill_port_8000.sh"
    fi
    
    if [ -f "update_bjorn.sh" ]; then
        chmod +x "update_bjorn.sh"
        chown $BJORN_USER:$BJORN_USER "update_bjorn.sh" 2>/dev/null || true
    fi
    
    # Fix permissions on all .sh files
    find "$BJORN_PATH" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    find "$BJORN_PATH" -name "*.sh" -type f -exec chown $BJORN_USER:$BJORN_USER {} \; 2>/dev/null || true
    
    check_success "Script permissions fixed"
}

# Restart BJORN service
restart_service() {
    log "INFO" "Restarting BJORN service..."
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "bjorn.service"; then
        log "WARNING" "BJORN service not found. Service may need to be created."
        echo -e "${YELLOW}BJORN service not found. You may need to run the installation script first.${NC}"
        return 0
    fi
    
    # Check if service is active
    if systemctl is-active --quiet bjorn.service 2>/dev/null; then
        log "INFO" "Stopping BJORN service..."
        systemctl stop bjorn.service
        sleep 1
    fi
    
    # Start the service
    log "INFO" "Starting BJORN service..."
    systemctl start bjorn.service
    
    # Wait a moment for service to start
    sleep 3
    
    # Check status with timeout
    if systemctl is-active --quiet bjorn.service 2>/dev/null; then
        log "SUCCESS" "BJORN service restarted successfully"
        echo -e "${GREEN}BJORN service restarted${NC}"
        systemctl status bjorn.service --no-pager -l | head -n 10
    else
        log "WARNING" "BJORN service may not have started properly"
        echo -e "${YELLOW}BJORN service status unclear. Check with: sudo systemctl status bjorn.service${NC}"
        echo -e "${YELLOW}Or view logs with: sudo journalctl -u bjorn.service -n 50${NC}"
        # Don't fail the update if service restart has issues
        return 0
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
    
    # Check service status and show recent errors if any
    if systemctl is-failed --quiet bjorn.service 2>/dev/null; then
        log "WARNING" "BJORN service is in failed state"
        echo -e "${YELLOW}Service failed to start. Recent errors:${NC}"
        journalctl -u bjorn.service -n 20 --no-pager 2>/dev/null | tail -n 10 || true
        echo ""
        echo -e "${YELLOW}To diagnose the issue, run:${NC}"
        echo -e "  sudo systemctl status bjorn.service"
        echo -e "  sudo journalctl -u bjorn.service -n 50"
    elif systemctl is-active --quiet bjorn.service 2>/dev/null; then
        log "SUCCESS" "BJORN service is running"
    else
        log "INFO" "BJORN service status unknown"
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
    
    # Fix script permissions
    show_progress "Fixing script permissions"
    fix_script_permissions || exit 1
    
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

