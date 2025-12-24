#!/bin/bash
# mount_external_nfs.sh - Mount external NFS share via WireGuard
#
# This script:
# 1. Verifies WireGuard VPN connectivity
# 2. Installs NFS client if needed
# 3. Mounts external NFS share
# 4. Configures automatic mounting

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

# Install NFS client
install_nfs_client() {
    log_info "Installing NFS client..."
    
    install_package nfs-common
    
    log_info "NFS client installed successfully"
}

# Verify WireGuard connectivity
verify_wireguard() {
    local wg_interface="${WG_INTERFACE:-wg0}"
    local nfs_server="${EXTERNAL_NFS_SERVER:?External NFS server not configured}"
    
    log_info "Verifying WireGuard connectivity..."
    
    # Check if WireGuard interface exists
    if ! ip link show "$wg_interface" >/dev/null 2>&1; then
        log_error "WireGuard interface $wg_interface not found"
        log_info "Please ensure WireGuard is configured and running"
        return 1
    fi
    
    # Check if WireGuard is active
    if ! wg show "$wg_interface" >/dev/null 2>&1; then
        log_error "WireGuard interface $wg_interface is not active"
        return 1
    fi
    
    log_info "WireGuard interface $wg_interface is active"
    
    # Test connectivity to NFS server
    log_info "Testing connectivity to NFS server: $nfs_server"
    
    if ping -c 3 -W 5 "$nfs_server" >/dev/null 2>&1; then
        log_info "Successfully reached NFS server"
        return 0
    else
        log_error "Cannot reach NFS server at $nfs_server"
        log_error "Please verify:"
        log_error "  1. WireGuard VPN is properly configured"
        log_error "  2. Server $nfs_server is accessible via VPN"
        log_error "  3. Firewall rules allow NFS traffic"
        return 1
    fi
}

# Check NFS server exports
check_nfs_exports() {
    local nfs_server="${EXTERNAL_NFS_SERVER:?External NFS server not configured}"
    local nfs_export="${EXTERNAL_NFS_EXPORT:?External NFS export not configured}"
    
    log_info "Checking NFS exports on $nfs_server..."
    
    # Try to list exports
    if showmount -e "$nfs_server" >/dev/null 2>&1; then
        log_info "Available NFS exports on $nfs_server:"
        showmount -e "$nfs_server" | while read -r line; do
            log_info "  $line"
        done
        
        # Check if our export exists
        if showmount -e "$nfs_server" | grep -q "$nfs_export"; then
            log_info "Export $nfs_export is available"
            return 0
        else
            log_warning "Export $nfs_export not found in server exports"
            log_warning "This may still work if the server allows it"
        fi
    else
        log_warning "Could not list exports from $nfs_server"
        log_warning "This may be due to firewall rules, proceeding anyway..."
    fi
    
    return 0
}

# Mount external NFS share
mount_external_nfs() {
    local nfs_server="${EXTERNAL_NFS_SERVER:?External NFS server not configured}"
    local nfs_export="${EXTERNAL_NFS_EXPORT:?External NFS export not configured}"
    local mount_point="${EXTERNAL_NFS_MOUNT_POINT:?External NFS mount point not configured}"
    local nfs_options="${EXTERNAL_NFS_OPTIONS:-rw,hard,intr,rsize=8192,wsize=8192}"
    
    log_info "Mounting external NFS share..."
    
    # Create mount point
    ensure_directory "$mount_point" "root:root" "0755"
    
    # Check if already mounted
    if is_mount_point "$mount_point"; then
        log_info "External NFS already mounted at $mount_point"
        
        # Verify it's the correct mount
        if mount | grep "$mount_point" | grep -q "$nfs_server:$nfs_export"; then
            log_info "Correct NFS share is mounted"
            return 0
        else
            log_warning "Different filesystem mounted at $mount_point, unmounting..."
            umount "$mount_point" || die "Failed to unmount $mount_point"
        fi
    fi
    
    # Mount NFS share
    log_info "Mounting $nfs_server:$nfs_export to $mount_point..."
    log_info "Options: $nfs_options"
    
    if retry mount -t nfs -o "$nfs_options" "$nfs_server:$nfs_export" "$mount_point"; then
        log_info "External NFS mounted successfully"
    else
        die "Failed to mount external NFS share"
    fi
    
    # Verify mount
    if is_mount_point "$mount_point"; then
        log_info "Mount verified successfully"
        
        # Show mount info
        log_info "Mount information:"
        df -h "$mount_point" | while read -r line; do
            log_info "  $line"
        done
    else
        die "Mount verification failed"
    fi
}

# Add to fstab for automatic mounting
configure_fstab() {
    local nfs_server="${EXTERNAL_NFS_SERVER}"
    local nfs_export="${EXTERNAL_NFS_EXPORT}"
    local mount_point="${EXTERNAL_NFS_MOUNT_POINT}"
    local nfs_options="${EXTERNAL_NFS_OPTIONS:-rw,hard,intr,rsize=8192,wsize=8192}"
    
    log_info "Configuring automatic mounting in /etc/fstab..."
    
    local nfs_url="$nfs_server:$nfs_export"
    
    # Check if entry already exists
    if grep -q "$nfs_url" /etc/fstab 2>/dev/null; then
        log_info "Entry already exists in /etc/fstab"
        return 0
    fi
    
    # Backup fstab
    backup_file /etc/fstab
    
    # Add entry with _netdev option (wait for network)
    echo "" >> /etc/fstab
    echo "# External NFS mount via WireGuard - Added by setup script" >> /etc/fstab
    echo "$nfs_url $mount_point nfs _netdev,$nfs_options 0 0" >> /etc/fstab
    
    log_info "Added entry to /etc/fstab"
}

# Create systemd mount unit for better dependency management
create_systemd_mount() {
    local mount_point="${EXTERNAL_NFS_MOUNT_POINT}"
    local nfs_server="${EXTERNAL_NFS_SERVER}"
    local nfs_export="${EXTERNAL_NFS_EXPORT}"
    local nfs_options="${EXTERNAL_NFS_OPTIONS:-rw,hard,intr,rsize=8192,wsize=8192}"
    
    # Convert mount point to systemd unit name
    # /mnt/external-nfs -> mnt-external\x2dnfs.mount
    local unit_name=$(systemd-escape -p --suffix=mount "$mount_point")
    local unit_file="/etc/systemd/system/$unit_name"
    
    log_info "Creating systemd mount unit: $unit_name"
    
    cat > "$unit_file" <<EOF
[Unit]
Description=External NFS Mount via WireGuard
After=network-online.target
Wants=network-online.target
# Depend on WireGuard if enabled
After=wg-quick@${WG_INTERFACE:-wg0}.service
Requires=wg-quick@${WG_INTERFACE:-wg0}.service

[Mount]
What=$nfs_server:$nfs_export
Where=$mount_point
Type=nfs
Options=_netdev,$nfs_options

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "Systemd mount unit created"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable the mount
    systemctl enable "$unit_name" || log_warning "Failed to enable $unit_name"
    
    log_info "Systemd mount unit configured"
}

# Test NFS mount
test_nfs_mount() {
    local mount_point="${EXTERNAL_NFS_MOUNT_POINT}"
    
    log_info "Testing NFS mount..."
    
    # Try to list directory
    if ls -la "$mount_point" >/dev/null 2>&1; then
        log_info "Successfully accessed mount point"
        log_info "Contents:"
        ls -lah "$mount_point" | head -n 10 | while read -r line; do
            log_info "  $line"
        done
    else
        log_warning "Could not list directory contents"
        log_warning "Check permissions on remote server"
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting external NFS mount setup..."
    
    # Check if external NFS is enabled
    if [ "${ENABLE_EXTERNAL_NFS:-no}" != "yes" ]; then
        log_info "External NFS mount is disabled in configuration"
        return 0
    fi
    
    # Acquire lock
    acquire_lock
    
    # Install NFS client
    install_nfs_client
    
    # Verify WireGuard connectivity
    if ! verify_wireguard; then
        log_error "WireGuard connectivity check failed"
        die "Cannot proceed without WireGuard connectivity"
    fi
    
    # Check NFS exports
    check_nfs_exports
    
    # Mount NFS share
    mount_external_nfs
    
    # Configure automatic mounting
    configure_fstab
    create_systemd_mount
    
    # Test mount
    test_nfs_mount
    
    log_info "External NFS mount setup completed successfully"
    return 0
}

# Run main function
main "$@"
