#!/bin/bash
# start_services.sh - Main orchestration script for DK-B-Server
#
# This script starts all services in the correct order:
# 1. Network (including WireGuard VPN)
# 2. iSCSI device mounting
# 3. Cache setup
# 4. Samba & NFS services
# 5. External NFS mount
# 6. Nextcloud client

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common functions
source "${SCRIPT_DIR}/common.sh"

# Check root privileges
check_root

# =============================================================================
# CONFIGURATION
# =============================================================================

# Service start delay (seconds between services)
SERVICE_DELAY="${SERVICE_START_DELAY:-5}"

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Print banner
print_banner() {
    log_info "========================================"
    log_info "  DK-B-Server Service Orchestration"
    log_info "========================================"
    log_info ""
}

# Print service order
print_service_order() {
    log_info "Service startup order:"
    log_info "  1. Network (including WireGuard VPN)"
    log_info "  2. iSCSI storage"
    log_info "  3. SSD cache"
    log_info "  4. Samba & NFS file sharing"
    log_info "  5. External NFS mount"
    log_info "  6. Nextcloud client"
    log_info ""
}

# Execute script with error handling
execute_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${script_name}"
    local description="$2"
    
    log_info "========================================"
    log_info "Starting: $description"
    log_info "Script: $script_name"
    log_info "========================================"
    
    # Check if script exists
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script_path"
        return 1
    fi
    
    # Make script executable
    chmod +x "$script_path"
    
    # Execute script
    if bash "$script_path"; then
        log_info "SUCCESS: $description completed"
        log_info ""
        
        # Wait before starting next service
        if [ $SERVICE_DELAY -gt 0 ]; then
            log_info "Waiting ${SERVICE_DELAY}s before next service..."
            sleep $SERVICE_DELAY
        fi
        
        return 0
    else
        log_error "FAILED: $description failed with exit code $?"
        return 1
    fi
}

# Step 1: Network initialization
setup_network() {
    execute_script "setup_network.sh" "Network initialization"
}

# Step 2: iSCSI storage
setup_iscsi() {
    execute_script "setup_iscsi.sh" "iSCSI storage setup"
}

# Step 3: Cache setup
setup_cache() {
    execute_script "setup_cache.sh" "SSD cache setup"
}

# Step 4: File sharing
setup_file_sharing() {
    execute_script "setup_samba_nfs.sh" "Samba & NFS setup"
}

# Step 5: External NFS mount
setup_external_nfs() {
    # Only run if enabled
    if [ "${ENABLE_EXTERNAL_NFS:-no}" = "yes" ]; then
        execute_script "mount_external_nfs.sh" "External NFS mount"
    else
        log_info "External NFS mount is disabled, skipping..."
        log_info ""
    fi
}

# Step 6: Nextcloud client
setup_nextcloud() {
    # Only run if enabled
    if [ "${ENABLE_NEXTCLOUD:-no}" = "yes" ]; then
        execute_script "setup_nextcloud_client.sh" "Nextcloud client setup"
    else
        log_info "Nextcloud client is disabled, skipping..."
        log_info ""
    fi
}

# Show final status
show_final_status() {
    log_info "========================================"
    log_info "  Final System Status"
    log_info "========================================"
    log_info ""
    
    # Network status
    log_info "Network:"
    if ip addr show | grep -q "inet "; then
        log_info "  ✓ Network is up"
    else
        log_info "  ✗ Network issues detected"
    fi
    
    # WireGuard status
    if [ "${ENABLE_WIREGUARD:-no}" = "yes" ]; then
        local wg_interface="${WG_INTERFACE:-wg0}"
        if wg show "$wg_interface" >/dev/null 2>&1; then
            log_info "  ✓ WireGuard VPN is active"
        else
            log_info "  ✗ WireGuard VPN is not active"
        fi
    fi
    
    log_info ""
    
    # iSCSI status
    log_info "Storage:"
    if iscsiadm -m session >/dev/null 2>&1; then
        log_info "  ✓ iSCSI connected"
    else
        log_info "  ✗ iSCSI not connected"
    fi
    
    local mount_point="${ISCSI_MOUNT_POINT:-/mnt/iscsi}"
    if mountpoint -q "$mount_point" 2>/dev/null; then
        log_info "  ✓ iSCSI mounted at $mount_point"
    else
        log_info "  ✗ iSCSI not mounted"
    fi
    
    log_info ""
    
    # Cache status
    log_info "Cache:"
    if ls /dev/bcache* >/dev/null 2>&1; then
        log_info "  ✓ bcache device active"
    else
        log_info "  ℹ No bcache device found"
    fi
    
    log_info ""
    
    # File sharing status
    log_info "File Sharing:"
    if systemctl is-active --quiet smbd; then
        log_info "  ✓ Samba is running"
    else
        log_info "  ✗ Samba is not running"
    fi
    
    if systemctl is-active --quiet nfs-server; then
        log_info "  ✓ NFS server is running"
    else
        log_info "  ✗ NFS server is not running"
    fi
    
    log_info ""
    
    # External NFS status
    if [ "${ENABLE_EXTERNAL_NFS:-no}" = "yes" ]; then
        log_info "External NFS:"
        local ext_mount="${EXTERNAL_NFS_MOUNT_POINT:-/mnt/external-nfs}"
        if mountpoint -q "$ext_mount" 2>/dev/null; then
            log_info "  ✓ External NFS mounted at $ext_mount"
        else
            log_info "  ✗ External NFS not mounted"
        fi
        log_info ""
    fi
    
    # Nextcloud status
    if [ "${ENABLE_NEXTCLOUD:-no}" = "yes" ]; then
        log_info "Nextcloud:"
        if systemctl is-active --quiet nextcloud-sync.timer; then
            log_info "  ✓ Nextcloud sync timer is active"
        else
            log_info "  ✗ Nextcloud sync timer is not active"
        fi
        log_info ""
    fi
    
    log_info "========================================"
}

# Create summary report
create_summary_report() {
    local report_file="${LOG_DIR}/startup-summary.txt"
    
    log_info "Creating summary report: $report_file"
    
    {
        echo "DK-B-Server Startup Summary"
        echo "Generated: $(date)"
        echo ""
        echo "=========================================="
        echo ""
        
        # System information
        echo "System Information:"
        echo "  Hostname: $(hostname)"
        echo "  Kernel: $(uname -r)"
        echo "  Memory: $(free -h | awk '/^Mem:/ {print $2}')"
        echo ""
        
        # Configuration
        echo "Configuration:"
        echo "  Config file: ${CONFIG_FILE:-/etc/dk-b-server.conf}"
        echo "  Log directory: ${LOG_DIR}"
        echo ""
        
        # Services
        echo "Services Status:"
        systemctl is-active smbd >/dev/null 2>&1 && echo "  Samba: Running" || echo "  Samba: Not running"
        systemctl is-active nfs-server >/dev/null 2>&1 && echo "  NFS: Running" || echo "  NFS: Not running"
        
        if [ "${ENABLE_WIREGUARD:-no}" = "yes" ]; then
            wg show "${WG_INTERFACE:-wg0}" >/dev/null 2>&1 && echo "  WireGuard: Running" || echo "  WireGuard: Not running"
        fi
        
        if [ "${ENABLE_NEXTCLOUD:-no}" = "yes" ]; then
            systemctl is-active nextcloud-sync.timer >/dev/null 2>&1 && echo "  Nextcloud: Running" || echo "  Nextcloud: Not running"
        fi
        
        echo ""
        
        # Mounts
        echo "Mount Points:"
        df -h | grep -E "(iscsi|nfs|bcache)" || echo "  No special mounts found"
        
    } > "$report_file"
    
    log_info "Summary report created"
}

# =============================================================================
# ERROR HANDLING
# =============================================================================

# Handle errors during startup
handle_error() {
    local exit_code=$?
    local failed_step="$1"
    
    log_error "========================================"
    log_error "  Startup Failed at: $failed_step"
    log_error "  Exit code: $exit_code"
    log_error "========================================"
    log_error ""
    log_error "Check logs for details:"
    log_error "  Log directory: ${LOG_DIR}"
    log_error ""
    log_error "To retry individual steps, run:"
    log_error "  ${SCRIPT_DIR}/setup_network.sh"
    log_error "  ${SCRIPT_DIR}/setup_iscsi.sh"
    log_error "  ${SCRIPT_DIR}/setup_cache.sh"
    log_error "  ${SCRIPT_DIR}/setup_samba_nfs.sh"
    log_error "  ${SCRIPT_DIR}/mount_external_nfs.sh"
    log_error "  ${SCRIPT_DIR}/setup_nextcloud_client.sh"
    
    exit $exit_code
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    # Print banner
    print_banner
    
    # Show configuration
    log_info "Configuration file: ${CONFIG_FILE:-/etc/dk-b-server.conf}"
    log_info "Log directory: ${LOG_DIR}"
    log_info ""
    
    # Print service order
    print_service_order
    
    # Acquire lock
    acquire_lock
    
    # Execute services in order
    setup_network || handle_error "Network initialization"
    
    setup_iscsi || handle_error "iSCSI setup"
    
    setup_cache || handle_error "Cache setup"
    
    setup_file_sharing || handle_error "File sharing setup"
    
    setup_external_nfs || handle_error "External NFS mount"
    
    setup_nextcloud || handle_error "Nextcloud client setup"
    
    # Show final status
    show_final_status
    
    # Create summary report
    create_summary_report
    
    log_info ""
    log_info "========================================"
    log_info "  All services started successfully!"
    log_info "========================================"
    log_info ""
    log_info "Review the summary report: ${LOG_DIR}/startup-summary.txt"
    log_info "For troubleshooting, check logs in: ${LOG_DIR}"
    
    return 0
}

# Run main function
main "$@"
