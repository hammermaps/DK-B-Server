#!/bin/bash
# setup_iscsi.sh - Configure and mount iSCSI storage
#
# This script:
# 1. Installs open-iscsi package
# 2. Configures iSCSI initiator
# 3. Discovers and connects to iSCSI target
# 4. Mounts iSCSI device

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
source "${SCRIPT_DIR}/common.sh"

# Check root privileges
check_root

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Install iSCSI packages
install_iscsi_packages() {
    log_info "Installing iSCSI packages..."
    
    install_package open-iscsi
    
    log_info "iSCSI packages installed successfully"
}

# Configure iSCSI initiator
configure_iscsi_initiator() {
    local initiator_name="${ISCSI_INITIATOR_NAME:-}"
    local initiator_config="/etc/iscsi/initiatorname.iscsi"
    
    log_info "Configuring iSCSI initiator..."
    
    # Backup original config
    backup_file "$initiator_config"
    
    if [ -n "$initiator_name" ]; then
        log_info "Setting custom initiator name: $initiator_name"
        echo "InitiatorName=$initiator_name" > "$initiator_config"
    else
        log_info "Using auto-generated initiator name"
        # Let the system generate one if not exists
        if [ ! -f "$initiator_config" ] || ! grep -q "^InitiatorName=" "$initiator_config"; then
            /sbin/iscsi-iname > /tmp/iscsi-iname.tmp
            echo "InitiatorName=$(cat /tmp/iscsi-iname.tmp)" > "$initiator_config"
            rm -f /tmp/iscsi-iname.tmp
        fi
    fi
    
    log_info "Initiator name: $(grep InitiatorName $initiator_config)"
    
    # Configure CHAP authentication if enabled
    if [ "${ISCSI_USE_CHAP:-no}" = "yes" ]; then
        configure_iscsi_chap
    fi
    
    # Enable automatic login
    log_info "Configuring automatic login..."
    sed -i 's/^node.startup = manual/node.startup = automatic/' /etc/iscsi/iscsid.conf 2>/dev/null || true
}

# Configure CHAP authentication
configure_iscsi_chap() {
    local iscsid_config="/etc/iscsi/iscsid.conf"
    
    log_info "Configuring CHAP authentication..."
    
    backup_file "$iscsid_config"
    
    # Enable CHAP
    sed -i 's/^#*node.session.auth.authmethod = .*/node.session.auth.authmethod = CHAP/' "$iscsid_config"
    sed -i "s/^#*node.session.auth.username = .*/node.session.auth.username = ${ISCSI_CHAP_USER}/" "$iscsid_config"
    sed -i "s/^#*node.session.auth.password = .*/node.session.auth.password = ${ISCSI_CHAP_PASSWORD}/" "$iscsid_config"
    
    log_info "CHAP authentication configured"
}

# Start iSCSI services
start_iscsi_services() {
    log_info "Starting iSCSI services..."
    
    # Enable and start iscsid
    enable_and_start_service iscsid
    
    # Enable open-iscsi service
    systemctl enable open-iscsi 2>/dev/null || true
    
    log_info "iSCSI services started"
}

# Discover iSCSI targets
discover_iscsi_target() {
    local target_portal="${ISCSI_TARGET_PORTAL:?iSCSI target portal not configured}"
    
    log_info "Discovering iSCSI targets at $target_portal..."
    
    # Perform discovery
    retry iscsiadm -m discovery -t st -p "$target_portal" || {
        die "Failed to discover iSCSI targets at $target_portal"
    }
    
    log_info "iSCSI target discovery completed"
    
    # Show discovered targets
    log_info "Discovered targets:"
    iscsiadm -m node | while read -r line; do
        log_info "  $line"
    done
}

# Connect to iSCSI target
connect_iscsi_target() {
    local target_portal="${ISCSI_TARGET_PORTAL:?iSCSI target portal not configured}"
    local target_iqn="${ISCSI_TARGET_IQN:?iSCSI target IQN not configured}"
    
    log_info "Connecting to iSCSI target: $target_iqn"
    
    # Check if already connected
    if iscsiadm -m session 2>/dev/null | grep -q "$target_iqn"; then
        log_info "Already connected to target: $target_iqn"
        return 0
    fi
    
    # Login to target
    retry iscsiadm -m node -T "$target_iqn" -p "$target_portal" --login || {
        die "Failed to connect to iSCSI target: $target_iqn"
    }
    
    log_info "Connected to iSCSI target successfully"
    
    # Wait for device to appear
    sleep 5
    
    # Show active sessions
    log_info "Active iSCSI sessions:"
    iscsiadm -m session | while read -r line; do
        log_info "  $line"
    done
}

# Find iSCSI device
find_iscsi_device() {
    local target_iqn="${ISCSI_TARGET_IQN:?iSCSI target IQN not configured}"
    
    log_info "Finding iSCSI device..."
    
    # Get device path from session
    local device_path=""
    
    # Try to find device through /dev/disk/by-path
    for disk in /dev/disk/by-path/*iscsi* /dev/disk/by-path/*"${target_iqn##*:}"*; do
        if [ -L "$disk" ] 2>/dev/null; then
            device_path=$(readlink -f "$disk")
            log_info "Found iSCSI device: $device_path (link: $disk)"
            echo "$device_path"
            return 0
        fi
    done
    
    # Alternative: search through /sys
    for host in /sys/class/iscsi_host/host*/device/session*/target*/*/block/*; do
        if [ -d "$host" ]; then
            device_path="/dev/$(basename "$host")"
            if [ -b "$device_path" ]; then
                log_info "Found iSCSI device: $device_path"
                echo "$device_path"
                return 0
            fi
        fi
    done
    
    log_error "Could not find iSCSI device"
    return 1
}

# Mount iSCSI device
mount_iscsi_device() {
    local mount_point="${ISCSI_MOUNT_POINT:?iSCSI mount point not configured}"
    local fs_type="${ISCSI_FS_TYPE:-ext4}"
    
    log_info "Mounting iSCSI device..."
    
    # Find device
    local device_path
    device_path=$(find_iscsi_device) || die "Failed to find iSCSI device"
    
    # Wait for device to be ready
    wait_for_device "$device_path" 30 || die "Device $device_path not ready"
    
    # Create mount point
    ensure_directory "$mount_point"
    
    # Check if already mounted
    if is_mount_point "$mount_point"; then
        log_info "iSCSI device already mounted at $mount_point"
        return 0
    fi
    
    # Check if device has a filesystem
    if ! blkid "$device_path" >/dev/null 2>&1; then
        log_warning "No filesystem found on $device_path"
        log_info "Creating $fs_type filesystem..."
        mkfs -t "$fs_type" "$device_path" || die "Failed to create filesystem"
    fi
    
    # Mount device
    log_info "Mounting $device_path to $mount_point..."
    mount -t "$fs_type" "$device_path" "$mount_point" || die "Failed to mount device"
    
    log_info "iSCSI device mounted successfully"
    
    # Add to fstab for persistence (using _netdev option)
    if ! grep -q "$device_path" /etc/fstab; then
        log_info "Adding entry to /etc/fstab..."
        backup_file /etc/fstab
        echo "$device_path $mount_point $fs_type _netdev,defaults 0 0" >> /etc/fstab
    fi
    
    # Show mount info
    log_info "Mount information:"
    df -h "$mount_point" | while read -r line; do
        log_info "  $line"
    done
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting iSCSI setup..."
    
    # Acquire lock
    acquire_lock
    
    # Install packages
    install_iscsi_packages
    
    # Configure initiator
    configure_iscsi_initiator
    
    # Start services
    start_iscsi_services
    
    # Discover targets
    discover_iscsi_target
    
    # Connect to target
    connect_iscsi_target
    
    # Mount device
    mount_iscsi_device
    
    log_info "iSCSI setup completed successfully"
    return 0
}

# Run main function
main "$@"
