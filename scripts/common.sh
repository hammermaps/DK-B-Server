#!/bin/bash
# Common functions and utilities for DK-B-Server scripts

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default configuration file location
CONFIG_FILE="${CONFIG_FILE:-/etc/dk-b-server.conf}"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "Warning: Configuration file not found at $CONFIG_FILE"
    echo "Using default values or script arguments"
fi

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

# Create log directory if it doesn't exist
LOG_DIR="${LOG_DIR:-/var/log/dk-b-server}"
mkdir -p "$LOG_DIR"

# Get current script name for logging
SCRIPT_NAME="$(basename "$0" .sh)"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"

# Log levels
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
CURRENT_LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check if we should log this level
    if [ ${LOG_LEVELS[$level]:-1} -ge ${LOG_LEVELS[$CURRENT_LOG_LEVEL]:-1} ]; then
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    fi
}

log_debug() { log "DEBUG" "$@"; }
log_info() { log "INFO" "$@"; }
log_warning() { log "WARNING" "$@"; }
log_error() { log "ERROR" "$@"; }

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Exit on error with message
die() {
    log_error "$@"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        die "This script must be run as root"
    fi
}

# =============================================================================
# RETRY LOGIC
# =============================================================================

# Retry a command with exponential backoff
retry() {
    local max_attempts="${MAX_RETRIES:-3}"
    local delay="${RETRY_DELAY:-10}"
    local attempt=1
    local exit_code=0
    
    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts: $*"
        
        if "$@"; then
            return 0
        else
            exit_code=$?
            log_warning "Command failed with exit code $exit_code (attempt $attempt/$max_attempts)"
            
            if [ $attempt -lt $max_attempts ]; then
                log_info "Retrying in $delay seconds..."
                sleep $delay
                delay=$((delay * 2))  # Exponential backoff
            fi
            
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts: $*"
    return $exit_code
}

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a package is installed
package_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

# Install package if not already installed
install_package() {
    local package="$1"
    
    if package_installed "$package"; then
        log_info "Package $package is already installed"
        return 0
    fi
    
    log_info "Installing package: $package"
    retry apt-get update -qq
    retry apt-get install -y "$package" || die "Failed to install $package"
    log_info "Package $package installed successfully"
}

# Check if a service is active
service_active() {
    systemctl is-active --quiet "$1"
}

# Check if a service is enabled
service_enabled() {
    systemctl is-enabled --quiet "$1"
}

# =============================================================================
# NETWORK FUNCTIONS
# =============================================================================

# Check if network is available
check_network() {
    local timeout="${NETWORK_TIMEOUT:-30}"
    local host="${1:-8.8.8.8}"
    
    log_info "Checking network connectivity..."
    
    if timeout $timeout ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
        log_info "Network is available"
        return 0
    else
        log_error "Network is not available"
        return 1
    fi
}

# Wait for network to be available
wait_for_network() {
    local max_wait="${NETWORK_TIMEOUT:-30}"
    local waited=0
    
    log_info "Waiting for network to be available..."
    
    while [ $waited -lt $max_wait ]; do
        if check_network; then
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    
    die "Network not available after ${max_wait}s"
}

# =============================================================================
# DEVICE FUNCTIONS
# =============================================================================

# Check if a device exists
device_exists() {
    [ -b "$1" ]
}

# Wait for device to appear
wait_for_device() {
    local device="$1"
    local timeout="${2:-60}"
    local waited=0
    
    log_info "Waiting for device $device..."
    
    while [ $waited -lt $timeout ]; do
        if device_exists "$device"; then
            log_info "Device $device is available"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    log_error "Device $device not available after ${timeout}s"
    return 1
}

# Check if a device is mounted
is_mounted() {
    local device="$1"
    mount | grep -q "^$device "
}

# Check if a path is a mount point
is_mount_point() {
    local path="$1"
    mountpoint -q "$path"
}

# =============================================================================
# FILE SYSTEM FUNCTIONS
# =============================================================================

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    local owner="${2:-root:root}"
    local perms="${3:-0755}"
    
    if [ ! -d "$dir" ]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || die "Failed to create directory: $dir"
        chown "$owner" "$dir"
        chmod "$perms" "$dir"
    fi
}

# Backup a file with timestamp
backup_file() {
    local file="$1"
    
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up $file to $backup"
        cp -a "$file" "$backup" || log_warning "Failed to backup $file"
    fi
}

# =============================================================================
# SERVICE MANAGEMENT
# =============================================================================

# Enable and start a service
enable_and_start_service() {
    local service="$1"
    
    log_info "Enabling service: $service"
    systemctl enable "$service" || log_warning "Failed to enable $service"
    
    log_info "Starting service: $service"
    systemctl start "$service" || die "Failed to start $service"
    
    sleep 2
    
    if service_active "$service"; then
        log_info "Service $service is running"
    else
        die "Service $service failed to start"
    fi
}

# Restart a service
restart_service() {
    local service="$1"
    
    log_info "Restarting service: $service"
    systemctl restart "$service" || die "Failed to restart $service"
    
    sleep 2
    
    if service_active "$service"; then
        log_info "Service $service restarted successfully"
    else
        die "Service $service failed to restart"
    fi
}

# =============================================================================
# LOCK FILE MANAGEMENT
# =============================================================================

LOCK_FILE="/var/lock/dk-b-server-$(basename "$0" .sh).lock"

# Acquire lock
acquire_lock() {
    local timeout="${1:-300}"  # 5 minutes default
    local waited=0
    
    while [ -f "$LOCK_FILE" ]; do
        if [ $waited -ge $timeout ]; then
            die "Could not acquire lock after ${timeout}s"
        fi
        log_info "Waiting for lock file to be released..."
        sleep 5
        waited=$((waited + 5))
    done
    
    echo $$ > "$LOCK_FILE"
    log_debug "Lock acquired (PID: $$)"
}

# Release lock
release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        log_debug "Lock released"
    fi
}

# Trap to ensure lock is released on exit
trap release_lock EXIT INT TERM

# =============================================================================
# INITIALIZATION
# =============================================================================

# Log script start
log_info "========================================"
log_info "Script started: $(basename "$0")"
log_info "========================================"
