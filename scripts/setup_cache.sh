#!/bin/bash
# setup_cache.sh - Setup SSD cache using bcache
#
# This script:
# 1. Installs bcache-tools
# 2. Configures /dev/md128 as cache device
# 3. Sets up bcache with writeback mode for iSCSI device
# 4. Optimizes cache settings

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

# Install bcache tools
install_bcache_tools() {
    log_info "Installing bcache tools..."
    
    install_package bcache-tools
    
    # Load bcache kernel module
    log_info "Loading bcache kernel module..."
    modprobe bcache || log_warning "Failed to load bcache module (may already be loaded)"
    
    # Ensure module loads on boot
    if ! grep -q "^bcache$" /etc/modules 2>/dev/null; then
        echo "bcache" >> /etc/modules
        log_info "Added bcache to /etc/modules for automatic loading"
    fi
    
    log_info "bcache tools installed successfully"
}

# Find iSCSI backing device
find_backing_device() {
    local mount_point="${ISCSI_MOUNT_POINT:?iSCSI mount point not configured}"
    
    log_info "Finding iSCSI backing device..."
    
    # Get device from mount point
    local device_path
    device_path=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null) || {
        log_error "Could not find mounted device at $mount_point"
        return 1
    }
    
    log_info "Found backing device: $device_path"
    echo "$device_path"
    return 0
}

# Check if device is already using bcache
is_bcache_device() {
    local device="$1"
    
    # Check if device is a bcache device
    if [[ "$device" =~ ^/dev/bcache[0-9]+$ ]]; then
        return 0
    fi
    
    # Check if device has bcache superblock
    if bcache-super-show "$device" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Prepare cache device
prepare_cache_device() {
    local cache_dev="${CACHE_DEVICE:?Cache device not configured}"
    
    log_info "Preparing cache device: $cache_dev"
    
    # Check if device exists
    if ! device_exists "$cache_dev"; then
        die "Cache device $cache_dev does not exist"
    fi
    
    # Check if device is already a cache device
    if is_bcache_device "$cache_dev"; then
        log_info "Device $cache_dev is already configured as bcache cache"
        return 0
    fi
    
    # Warn user about data loss
    log_warning "This will erase all data on $cache_dev!"
    
    # Check device size
    local cache_size_bytes
    cache_size_bytes=$(blockdev --getsize64 "$cache_dev" 2>/dev/null || echo "0")
    local cache_size_gb=$((cache_size_bytes / 1024 / 1024 / 1024))
    log_info "Cache device size: ${cache_size_gb}GB"
    
    # Format as cache device
    log_info "Formatting $cache_dev as bcache cache device..."
    make-bcache -C "$cache_dev" --wipe-bcache || die "Failed to create cache device"
    
    log_info "Cache device prepared successfully"
    
    # Wait for cache device to register
    sleep 2
}

# Prepare backing device
prepare_backing_device() {
    local mount_point="${ISCSI_MOUNT_POINT:?iSCSI mount point not configured}"
    
    log_info "Preparing backing device..."
    
    # Find backing device
    local backing_dev
    backing_dev=$(find_backing_device) || die "Failed to find backing device"
    
    # Check if already a bcache device
    if is_bcache_device "$backing_dev"; then
        log_info "Device $backing_dev is already configured for bcache"
        echo "$backing_dev"
        return 0
    fi
    
    # Need to unmount before converting
    log_info "Unmounting $mount_point..."
    umount "$mount_point" || die "Failed to unmount $mount_point"
    
    # Format as backing device
    log_info "Formatting $backing_dev as bcache backing device..."
    log_warning "This will preserve existing data but may take some time..."
    make-bcache -B "$backing_dev" --wipe-bcache || die "Failed to create backing device"
    
    log_info "Backing device prepared successfully"
    
    # Wait for bcache device to appear
    sleep 3
    
    # Find new bcache device
    local bcache_dev=""
    for dev in /dev/bcache*; do
        if [ -b "$dev" ]; then
            bcache_dev="$dev"
            break
        fi
    done
    
    if [ -z "$bcache_dev" ]; then
        die "Failed to find bcache device after creation"
    fi
    
    log_info "New bcache device: $bcache_dev"
    
    # Remount using bcache device
    log_info "Remounting as bcache device..."
    mount "$bcache_dev" "$mount_point" || die "Failed to remount bcache device"
    
    # Update fstab
    backup_file /etc/fstab
    sed -i "s|^$backing_dev|$bcache_dev|" /etc/fstab
    
    echo "$bcache_dev"
    return 0
}

# Attach cache to backing device
attach_cache() {
    local cache_dev="${CACHE_DEVICE:?Cache device not configured}"
    
    log_info "Attaching cache device to backing device..."
    
    # Find cache set UUID
    local cache_uuid
    cache_uuid=$(bcache-super-show "$cache_dev" | grep "cset.uuid" | awk '{print $2}')
    
    if [ -z "$cache_uuid" ]; then
        die "Failed to get cache UUID from $cache_dev"
    fi
    
    log_info "Cache UUID: $cache_uuid"
    
    # Find bcache device
    local bcache_dev=""
    for dev in /dev/bcache*; do
        if [ -b "$dev" ]; then
            bcache_dev="$dev"
            break
        fi
    done
    
    if [ -z "$bcache_dev" ]; then
        die "No bcache device found"
    fi
    
    log_info "Attaching cache to $bcache_dev..."
    
    # Get bcache number
    local bcache_num="${bcache_dev#/dev/bcache}"
    
    # Attach cache
    echo "$cache_uuid" > "/sys/block/bcache${bcache_num}/bcache/attach" 2>/dev/null || {
        log_warning "Cache may already be attached"
    }
    
    log_info "Cache attached successfully"
}

# Configure cache settings
configure_cache_settings() {
    local cache_mode="${CACHE_MODE:-writeback}"
    local sequential_cutoff="${CACHE_SEQUENTIAL_CUTOFF:-4}"
    
    log_info "Configuring cache settings..."
    
    # Find bcache device
    local bcache_dev=""
    for dev in /dev/bcache*; do
        if [ -b "$dev" ]; then
            bcache_dev="$dev"
            break
        fi
    done
    
    if [ -z "$bcache_dev" ]; then
        log_warning "No bcache device found for configuration"
        return 1
    fi
    
    local bcache_num="${bcache_dev#/dev/bcache}"
    local bcache_sys="/sys/block/bcache${bcache_num}/bcache"
    
    # Set cache mode
    log_info "Setting cache mode to: $cache_mode"
    echo "$cache_mode" > "${bcache_sys}/cache_mode" 2>/dev/null || {
        log_warning "Failed to set cache mode"
    }
    
    # Set sequential cutoff (in KB)
    local cutoff_kb=$((sequential_cutoff * 1024))
    log_info "Setting sequential cutoff to: ${sequential_cutoff}MB"
    echo "$cutoff_kb" > "${bcache_sys}/sequential_cutoff" 2>/dev/null || {
        log_warning "Failed to set sequential cutoff"
    }
    
    # Set writeback percent (how much of cache to use before flushing)
    if [ "$cache_mode" = "writeback" ]; then
        log_info "Configuring writeback settings..."
        echo "10" > "${bcache_sys}/writeback_percent" 2>/dev/null || true
        echo "40" > "${bcache_sys}/writeback_rate_minimum" 2>/dev/null || true
    fi
    
    log_info "Cache settings configured"
}

# Show cache status
show_cache_status() {
    log_info "Cache Status:"
    log_info "----------------------------------------"
    
    # Find bcache devices
    for dev in /dev/bcache*; do
        if [ -b "$dev" ]; then
            local bcache_num="${dev#/dev/bcache}"
            local bcache_sys="/sys/block/bcache${bcache_num}/bcache"
            
            log_info "Device: $dev"
            
            if [ -f "${bcache_sys}/cache_mode" ]; then
                log_info "  Cache Mode: $(cat "${bcache_sys}/cache_mode")"
            fi
            
            if [ -f "${bcache_sys}/state" ]; then
                log_info "  State: $(cat "${bcache_sys}/state")"
            fi
            
            if [ -f "${bcache_sys}/dirty_data" ]; then
                log_info "  Dirty Data: $(cat "${bcache_sys}/dirty_data")"
            fi
            
            if [ -d "${bcache_sys}/cache" ]; then
                log_info "  Cache attached: Yes"
            else
                log_info "  Cache attached: No"
            fi
        fi
    done
    
    log_info "----------------------------------------"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting cache setup..."
    
    # Acquire lock
    acquire_lock
    
    # Install tools
    install_bcache_tools
    
    # Prepare cache device
    prepare_cache_device
    
    # Prepare backing device
    local bcache_dev
    bcache_dev=$(prepare_backing_device)
    
    # Attach cache
    attach_cache
    
    # Configure settings
    configure_cache_settings
    
    # Show status
    show_cache_status
    
    log_info "Cache setup completed successfully"
    log_info "Note: Cache performance will improve as it warms up"
    return 0
}

# Run main function
main "$@"
