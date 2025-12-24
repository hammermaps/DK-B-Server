# DK-B-Server - Automated Infrastructure Setup Scripts

Comprehensive automation scripts for Ubuntu Server 24.04 that configure iSCSI storage, SSD caching, file sharing (Samba/NFS), WireGuard VPN, and Nextcloud synchronization.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Usage](#usage)
- [Service Management](#service-management)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Monitoring](#monitoring)

## Overview

The DK-B-Server automation scripts provide a complete solution for setting up a high-performance file server with:

- **Network**: Automatic network initialization with optional WireGuard VPN
- **Storage**: iSCSI target mounting with SSD cache acceleration
- **Caching**: bcache setup using 110GB SSD RAID array (/dev/md128)
- **File Sharing**: Samba and NFS server configuration
- **External Storage**: NFS mount from remote server via WireGuard
- **Synchronization**: Automated Nextcloud client with scheduled sync

All services are started in the correct dependency order with robust error handling and logging.

## Features

### ✅ Comprehensive Automation
- One-command setup for all services
- Idempotent scripts (safe to run multiple times)
- Automatic dependency resolution
- Robust error handling and retry logic

### ✅ Performance Optimized
- bcache writeback mode utilizing 16GB RAM
- Optimized Samba and NFS configurations
- Parallel service startup where possible

### ✅ Production Ready
- Systemd integration for all services
- Automatic startup on boot
- Comprehensive logging
- Lock file management to prevent conflicts

### ✅ Secure by Design
- CHAP authentication support for iSCSI
- Secure credential storage
- Network dependency management
- Service isolation

## System Requirements

- **OS**: Ubuntu Server 24.04 LTS
- **RAM**: 16 GB (minimum)
- **Storage**: 
  - SSD RAID array at /dev/md128 (110GB) for cache
  - Network-attached iSCSI storage
- **Network**: 
  - Active network connection
  - Optional: WireGuard VPN for external NFS access
- **Privileges**: Root access required

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/hammermaps/DK-B-Server.git
cd DK-B-Server
```

### 2. Configure

```bash
# Copy example configuration
sudo cp config/dk-b-server.conf.example /etc/dk-b-server.conf

# Edit configuration with your settings
sudo nano /etc/dk-b-server.conf
```

**Minimum required configuration:**
```bash
# iSCSI settings
ISCSI_TARGET_PORTAL="192.168.1.100:3260"
ISCSI_TARGET_IQN="iqn.2024-01.com.example:storage.target01"

# WireGuard (if needed)
ENABLE_WIREGUARD="yes"
# Ensure /etc/wireguard/wg0.conf exists

# External NFS (if needed)
ENABLE_EXTERNAL_NFS="yes"
EXTERNAL_NFS_SERVER="10.0.0.5"
EXTERNAL_NFS_EXPORT="/srv/shared"

# Nextcloud (if needed)
ENABLE_NEXTCLOUD="yes"
NEXTCLOUD_SERVER_URL="https://nextcloud.example.com"
NEXTCLOUD_USER="your-username"
NEXTCLOUD_PASSWORD="your-password"
```

### 3. Run Setup

```bash
# Run the main orchestration script
sudo ./scripts/start_services.sh
```

This will automatically:
1. Initialize network and WireGuard VPN
2. Connect and mount iSCSI storage
3. Setup SSD cache with bcache
4. Configure and start Samba & NFS
5. Mount external NFS share
6. Setup Nextcloud sync

## Detailed Setup

### Individual Script Execution

You can run scripts individually for testing or troubleshooting:

#### Network Setup
```bash
sudo ./scripts/setup_network.sh
```
- Verifies network connectivity
- Starts WireGuard VPN if enabled
- Tests VPN connectivity

#### iSCSI Storage
```bash
sudo ./scripts/setup_iscsi.sh
```
- Installs open-iscsi packages
- Configures initiator
- Discovers and connects to target
- Mounts iSCSI device at `/mnt/iscsi`

#### SSD Cache
```bash
sudo ./scripts/setup_cache.sh
```
- Installs bcache-tools
- Configures /dev/md128 as cache device
- Sets up writeback caching
- Optimizes cache parameters

#### File Sharing
```bash
sudo ./scripts/setup_samba_nfs.sh
```
- Installs Samba and NFS servers
- Configures shares for iSCSI storage
- Starts services
- Shows access information

#### External NFS Mount
```bash
sudo ./scripts/mount_external_nfs.sh
```
- Verifies WireGuard connectivity
- Mounts external NFS share
- Configures automatic mounting

#### Nextcloud Client
```bash
sudo ./scripts/setup_nextcloud_client.sh
```
- Installs Nextcloud client
- Creates sync script
- Sets up systemd timer (5-minute interval)
- Tests initial sync

## Configuration

### Configuration File

The main configuration file is located at `/etc/dk-b-server.conf`. Copy from the example:

```bash
sudo cp config/dk-b-server.conf.example /etc/dk-b-server.conf
```

### Key Configuration Sections

#### Network Configuration
```bash
ENABLE_WIREGUARD="yes"           # Enable WireGuard VPN
WG_INTERFACE="wg0"               # WireGuard interface name
WG_CONFIG="/etc/wireguard/wg0.conf"  # WireGuard config file
```

**Note**: You must create the WireGuard configuration file manually before running the scripts.

#### iSCSI Configuration
```bash
ISCSI_TARGET_PORTAL="192.168.1.100:3260"
ISCSI_TARGET_IQN="iqn.2024-01.com.example:storage.target01"
ISCSI_MOUNT_POINT="/mnt/iscsi"
ISCSI_FS_TYPE="ext4"
```

#### Cache Configuration
```bash
CACHE_DEVICE="/dev/md128"        # SSD RAID array
CACHE_MODE="writeback"           # Best performance with 16GB RAM
CACHE_SEQUENTIAL_CUTOFF="4"     # Skip cache for large sequential I/O
```

#### File Sharing Configuration
```bash
SAMBA_SHARE_NAME="iscsi-storage"
SAMBA_GUEST_OK="yes"
NFS_ALLOWED_NETWORKS="192.168.1.0/24 10.0.0.0/24"
NFS_OPTIONS="rw,sync,no_subtree_check,no_root_squash"
```

#### External NFS Configuration
```bash
ENABLE_EXTERNAL_NFS="yes"
EXTERNAL_NFS_SERVER="10.0.0.5"
EXTERNAL_NFS_EXPORT="/srv/shared"
EXTERNAL_NFS_MOUNT_POINT="/mnt/external-nfs"
```

#### Nextcloud Configuration
```bash
ENABLE_NEXTCLOUD="yes"
NEXTCLOUD_SERVER_URL="https://nextcloud.example.com"
NEXTCLOUD_USER="admin"
NEXTCLOUD_PASSWORD="your-app-password"
NEXTCLOUD_LOCAL_DIR="/mnt/iscsi/nextcloud-sync"
NEXTCLOUD_SYNC_INTERVAL="5"     # Minutes
```

## Usage

### Starting All Services

```bash
sudo /usr/local/bin/dk-b-server-start
# Or directly:
sudo ./scripts/start_services.sh
```

### Checking Service Status

```bash
# Samba
sudo systemctl status smbd nmbd

# NFS
sudo systemctl status nfs-server

# WireGuard
sudo wg show

# iSCSI
sudo iscsiadm -m session

# Nextcloud sync
sudo systemctl status nextcloud-sync.timer
sudo systemctl list-timers nextcloud-sync.timer
```

### Viewing Logs

```bash
# All logs are in /var/log/dk-b-server/
ls -lh /var/log/dk-b-server/

# View specific log
sudo tail -f /var/log/dk-b-server/start_services.log

# Nextcloud sync log
sudo tail -f /var/log/dk-b-server/nextcloud-sync.log
```

### Manual Nextcloud Sync

```bash
# Trigger manual sync
sudo systemctl start nextcloud-sync.service

# Check sync status
sudo systemctl status nextcloud-sync.service
```

## Service Management

### Automatic Startup

All services are configured to start automatically on boot:

```bash
# iSCSI (automatic)
sudo systemctl enable open-iscsi

# Samba
sudo systemctl enable smbd nmbd

# NFS
sudo systemctl enable nfs-server

# WireGuard
sudo systemctl enable wg-quick@wg0

# Nextcloud sync timer
sudo systemctl enable nextcloud-sync.timer
```

### Starting/Stopping Services

```bash
# Stop all file sharing services
sudo systemctl stop smbd nmbd nfs-server

# Start all file sharing services
sudo systemctl start smbd nmbd nfs-server

# Restart a service
sudo systemctl restart smbd
```

### Unmounting Storage

```bash
# Unmount external NFS
sudo umount /mnt/external-nfs

# Unmount iSCSI (stop all services first!)
sudo systemctl stop smbd nmbd nfs-server
sudo umount /mnt/iscsi
sudo iscsiadm -m node -u  # Logout from all targets
```

## Troubleshooting

### Network Issues

**Problem**: Network not available

```bash
# Check network interfaces
ip addr show

# Check default route
ip route show

# Test connectivity
ping -c 3 8.8.8.8
```

### WireGuard Issues

**Problem**: WireGuard VPN not connecting

```bash
# Check WireGuard status
sudo wg show

# Check configuration
sudo wg-quick down wg0
sudo wg-quick up wg0

# View logs
sudo journalctl -u wg-quick@wg0 -f
```

### iSCSI Issues

**Problem**: Cannot connect to iSCSI target

```bash
# Check network connectivity to target
ping 192.168.1.100

# Discover targets manually
sudo iscsiadm -m discovery -t st -p 192.168.1.100:3260

# Check current sessions
sudo iscsiadm -m session

# Restart iSCSI service
sudo systemctl restart iscsid open-iscsi
```

**Problem**: iSCSI device not mounting

```bash
# Check if device exists
ls -l /dev/disk/by-path/*iscsi*

# Check filesystem
sudo blkid /dev/sdX  # Replace with actual device

# Try manual mount
sudo mount /dev/sdX /mnt/iscsi
```

### Cache Issues

**Problem**: bcache not working

```bash
# Check bcache devices
ls -l /dev/bcache*

# Check cache status
cat /sys/block/bcache0/bcache/state
cat /sys/block/bcache0/bcache/cache_mode

# View cache statistics
cat /sys/block/bcache0/bcache/stats_total/*
```

### Samba/NFS Issues

**Problem**: Cannot access Samba share

```bash
# Test Samba configuration
sudo testparm

# Check if service is running
sudo systemctl status smbd

# Test local connection
smbclient -L localhost -N

# Check firewall
sudo ufw status
```

**Problem**: Cannot mount NFS export

```bash
# Check NFS exports
sudo exportfs -v

# Test local mount
sudo showmount -e localhost

# Check if service is running
sudo systemctl status nfs-server
```

### Nextcloud Issues

**Problem**: Nextcloud sync failing

```bash
# Check sync logs
sudo tail -50 /var/log/dk-b-server/nextcloud-sync.log

# Test credentials manually
nextcloudcmd --version
nextcloudcmd --user your-user --password your-pass \
  /tmp/test https://nextcloud.example.com/

# Check timer status
sudo systemctl status nextcloud-sync.timer
sudo systemctl status nextcloud-sync.service
```

### General Troubleshooting

```bash
# Check all service logs
sudo journalctl -xe

# Check disk space
df -h

# Check system resources
free -h
top

# View startup summary
cat /var/log/dk-b-server/startup-summary.txt
```

## Security Considerations

### Credentials

**Important**: Store credentials securely!

- Use strong passwords for all services
- Consider using Nextcloud app passwords instead of main password
- Protect configuration file:
  ```bash
  sudo chmod 600 /etc/dk-b-server.conf
  ```

### Network Security

- Use WireGuard VPN for external access
- Configure firewall rules:
  ```bash
  sudo ufw allow 445/tcp   # Samba
  sudo ufw allow 2049/tcp  # NFS
  sudo ufw allow 51820/udp # WireGuard
  ```
- Restrict NFS exports to specific networks
- Enable CHAP authentication for iSCSI if possible

### File Permissions

- Review Samba and NFS share permissions
- Use appropriate user/group ownership
- Consider using SELinux or AppArmor for additional security

## Monitoring

### Performance Monitoring

```bash
# Monitor iSCSI performance
iostat -x 5

# Monitor cache hit rate
watch -n 5 'cat /sys/block/bcache0/bcache/stats_five_minute/*'

# Monitor network traffic
iftop -i wg0

# Monitor Samba connections
sudo smbstatus
```

### Log Monitoring

```bash
# Monitor all DK-B-Server logs
sudo tail -f /var/log/dk-b-server/*.log

# Monitor system logs
sudo journalctl -f

# Monitor specific service
sudo journalctl -u nfs-server -f
```

### Automated Monitoring

Consider setting up monitoring tools:

- **Prometheus + Grafana**: System and service metrics
- **Nagios/Icinga**: Service availability monitoring
- **Netdata**: Real-time performance monitoring

### Health Checks

Create a cron job for regular health checks:

```bash
# Add to /etc/cron.hourly/dk-b-server-health
#!/bin/bash
systemctl is-active smbd nfs-server || \
  echo "Service down!" | mail -s "DK-B-Server Alert" admin@example.com
```

## Backup and Recovery

### Configuration Backup

```bash
# Backup all configurations
sudo tar czf /backup/dk-b-server-config-$(date +%Y%m%d).tar.gz \
  /etc/dk-b-server.conf \
  /etc/wireguard/ \
  /etc/iscsi/ \
  /etc/samba/ \
  /etc/exports
```

### Recovery

```bash
# Restore configuration
sudo tar xzf /backup/dk-b-server-config-YYYYMMDD.tar.gz -C /

# Re-run setup
sudo ./scripts/start_services.sh
```

## Advanced Configuration

### Custom Cache Settings

Edit `/etc/dk-b-server.conf` and tune bcache:

```bash
CACHE_MODE="writeback"              # or "writethrough"
CACHE_SEQUENTIAL_CUTOFF="4"        # MB, bypass cache for large files
```

After changes:
```bash
sudo ./scripts/setup_cache.sh
```

### Custom Sync Schedule

Modify Nextcloud sync interval:

```bash
# Edit timer
sudo systemctl edit nextcloud-sync.timer

# Add under [Timer]:
[Timer]
OnUnitActiveSec=10min  # Change from 5min to 10min

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart nextcloud-sync.timer
```

## Support

### Getting Help

1. Check logs in `/var/log/dk-b-server/`
2. Review this README and troubleshooting section
3. Check individual script help: `./scripts/setup_network.sh --help`
4. Open an issue on GitHub: https://github.com/hammermaps/DK-B-Server/issues

### Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes
4. Submit a pull request

## License

This project is provided as-is for use with Ubuntu Server 24.04.

## Acknowledgments

- Ubuntu Server community
- bcache developers
- Samba and NFS projects
- WireGuard VPN
- Nextcloud

---

**Last Updated**: December 2024
**Version**: 1.0.0
