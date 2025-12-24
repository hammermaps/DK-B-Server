#!/bin/bash
# setup_network.sh - Initialize network and optionally start WireGuard VPN
#
# This script:
# 1. Checks network connectivity
# 2. Optionally starts WireGuard VPN
# 3. Verifies connectivity through VPN if enabled

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

# Check and wait for basic network connectivity
check_basic_network() {
    log_info "Checking basic network connectivity..."
    
    if ! wait_for_network; then
        die "Basic network connectivity check failed"
    fi
    
    log_info "Basic network is operational"
}

# Install WireGuard if needed
install_wireguard() {
    log_info "Checking WireGuard installation..."
    
    if command_exists wg; then
        log_info "WireGuard is already installed"
        return 0
    fi
    
    log_info "Installing WireGuard..."
    install_package wireguard
    install_package wireguard-tools
    
    log_info "WireGuard installed successfully"
}

# Setup WireGuard VPN
setup_wireguard() {
    local wg_interface="${WG_INTERFACE:-wg0}"
    local wg_config="${WG_CONFIG:-/etc/wireguard/${wg_interface}.conf}"
    
    log_info "Setting up WireGuard VPN interface: $wg_interface"
    
    # Check if config file exists
    if [ ! -f "$wg_config" ]; then
        log_error "WireGuard configuration file not found: $wg_config"
        log_info "Please create the configuration file first"
        log_info "Example location: $wg_config"
        return 1
    fi
    
    # Install WireGuard if needed
    install_wireguard
    
    # Check if interface is already up
    if ip link show "$wg_interface" >/dev/null 2>&1; then
        log_info "WireGuard interface $wg_interface already exists"
        
        # Check if it's actually running
        if wg show "$wg_interface" >/dev/null 2>&1; then
            log_info "WireGuard VPN is already active"
            return 0
        fi
    fi
    
    # Start WireGuard interface
    log_info "Starting WireGuard interface: $wg_interface"
    retry wg-quick up "$wg_interface" || {
        log_error "Failed to start WireGuard interface"
        return 1
    }
    
    # Wait a moment for VPN to establish
    sleep 3
    
    # Verify VPN is up
    if wg show "$wg_interface" >/dev/null 2>&1; then
        log_info "WireGuard VPN started successfully"
        log_info "$(wg show "$wg_interface")"
        
        # Enable at boot
        log_info "Enabling WireGuard at boot"
        systemctl enable "wg-quick@${wg_interface}" 2>/dev/null || true
        
        return 0
    else
        log_error "WireGuard VPN failed to start properly"
        return 1
    fi
}

# Test VPN connectivity
test_vpn_connectivity() {
    local test_host="${1:-10.0.0.1}"  # Default to common VPN gateway
    
    log_info "Testing VPN connectivity to $test_host..."
    
    if ping -c 3 -W 5 "$test_host" >/dev/null 2>&1; then
        log_info "VPN connectivity test successful"
        return 0
    else
        log_warning "VPN connectivity test failed for $test_host"
        log_warning "This may be expected if the test host is not configured"
        return 1
    fi
}

# Display network status
show_network_status() {
    log_info "Network Status:"
    log_info "----------------------------------------"
    
    # Show IP addresses
    log_info "Network Interfaces:"
    ip -brief addr show | while read -r line; do
        log_info "  $line"
    done
    
    # Show default route
    log_info ""
    log_info "Default Route:"
    ip route show default | while read -r line; do
        log_info "  $line"
    done
    
    # Show WireGuard status if enabled
    if [ "${ENABLE_WIREGUARD:-no}" = "yes" ]; then
        local wg_interface="${WG_INTERFACE:-wg0}"
        if wg show "$wg_interface" >/dev/null 2>&1; then
            log_info ""
            log_info "WireGuard Status:"
            wg show "$wg_interface" | while read -r line; do
                log_info "  $line"
            done
        fi
    fi
    
    log_info "----------------------------------------"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    log_info "Starting network initialization..."
    
    # Acquire lock
    acquire_lock
    
    # Check basic network connectivity
    check_basic_network
    
    # Setup WireGuard if enabled
    if [ "${ENABLE_WIREGUARD:-no}" = "yes" ]; then
        log_info "WireGuard VPN is enabled in configuration"
        
        if setup_wireguard; then
            log_info "WireGuard VPN setup completed"
            
            # Test VPN connectivity if test host is configured
            if [ -n "${VPN_TEST_HOST:-}" ]; then
                test_vpn_connectivity "$VPN_TEST_HOST"
            fi
        else
            log_warning "WireGuard VPN setup failed, continuing without VPN"
        fi
    else
        log_info "WireGuard VPN is disabled in configuration"
    fi
    
    # Show final network status
    show_network_status
    
    log_info "Network initialization completed successfully"
    return 0
}

# Run main function
main "$@"
