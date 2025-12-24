# Quick Reference Guide

## One-Line Commands

### Setup and Start

```bash
# Complete setup
sudo ./scripts/start_services.sh

# Individual components
sudo ./scripts/setup_network.sh
sudo ./scripts/setup_iscsi.sh
sudo ./scripts/setup_cache.sh
sudo ./scripts/setup_samba_nfs.sh
sudo ./scripts/mount_external_nfs.sh
sudo ./scripts/setup_nextcloud_client.sh
```

### Service Management

```bash
# Status checks
sudo systemctl status smbd nmbd nfs-server
sudo iscsiadm -m session
sudo wg show
sudo systemctl status nextcloud-sync.timer

# Restart services
sudo systemctl restart smbd nmbd
sudo systemctl restart nfs-server

# View logs
sudo tail -f /var/log/dk-b-server/start_services.log
sudo journalctl -u smbd -f
```

### Network

```bash
# WireGuard
sudo wg-quick up wg0
sudo wg-quick down wg0
sudo wg show

# Test connectivity
ping -c 3 8.8.8.8
ip addr show
ip route show
```

### iSCSI

```bash
# Session management
sudo iscsiadm -m session                    # Show sessions
sudo iscsiadm -m node                       # Show nodes
sudo iscsiadm -m discovery -t st -p IP:PORT # Discover targets
sudo iscsiadm -m node -u                    # Logout all
sudo iscsiadm -m node -T IQN -p IP --login  # Login specific

# Device info
ls -l /dev/disk/by-path/*iscsi*
lsblk | grep sd
```

### Cache

```bash
# bcache status
ls -l /dev/bcache*
cat /sys/block/bcache0/bcache/state
cat /sys/block/bcache0/bcache/cache_mode
cat /sys/block/bcache0/bcache/dirty_data

# Cache statistics
watch -n 5 'cat /sys/block/bcache0/bcache/stats_five_minute/*'

# Change cache mode
echo writethrough > /sys/block/bcache0/bcache/cache_mode
echo writeback > /sys/block/bcache0/bcache/cache_mode
```

### Samba

```bash
# Status
sudo smbstatus                  # Show connections
sudo testparm                   # Test config
smbclient -L localhost -N       # List shares

# Restart
sudo systemctl restart smbd nmbd

# Access
# Windows: \\SERVER-IP\iscsi-storage
# Linux:   smb://SERVER-IP/iscsi-storage
```

### NFS

```bash
# Status
sudo exportfs -v                # Show exports
sudo showmount -e localhost     # Show mounts
nfsstat                         # Statistics

# Manage exports
sudo exportfs -ra               # Re-export all
sudo exportfs -ua               # Unexport all

# Client mount
sudo mount -t nfs SERVER:/mnt/iscsi /mnt/share
```

### Nextcloud

```bash
# Manual sync
sudo systemctl start nextcloud-sync.service

# Check status
sudo systemctl status nextcloud-sync.timer
sudo systemctl list-timers nextcloud-sync.timer

# View logs
sudo tail -f /var/log/dk-b-server/nextcloud-sync.log

# Change interval (edit timer)
sudo systemctl edit nextcloud-sync.timer
```

### Monitoring

```bash
# System resources
htop
free -h
df -h

# I/O performance
iostat -x 5
iotop

# Network
iftop
nethogs
ss -tunap | grep -E '445|2049|3260'

# Samba performance
sudo smbstatus
watch -n 2 sudo smbstatus

# Cache performance
watch -n 5 'cat /sys/block/bcache0/bcache/stats_total/cache_hits'
watch -n 5 'cat /sys/block/bcache0/bcache/stats_total/cache_misses'
```

### Troubleshooting

```bash
# Check all logs
ls -lh /var/log/dk-b-server/
sudo tail -100 /var/log/dk-b-server/*.log

# System logs
sudo journalctl -xe
sudo journalctl -u smbd -f
sudo journalctl -u nfs-server -f

# Network issues
ping -c 3 8.8.8.8
traceroute 8.8.8.8
sudo netstat -tunap

# Storage issues
lsblk
sudo fdisk -l
df -h
sudo mount | grep -E 'iscsi|nfs|bcache'

# Process check
ps aux | grep -E 'smbd|nfsd|iscsid'
```

### Configuration

```bash
# Edit main config
sudo nano /etc/dk-b-server.conf

# Reload after changes
sudo ./scripts/start_services.sh

# View current config
cat /etc/dk-b-server.conf | grep -v '^#' | grep -v '^$'
```

### Backup & Restore

```bash
# Backup configuration
sudo tar czf ~/dk-b-backup-$(date +%Y%m%d).tar.gz \
  /etc/dk-b-server.conf \
  /etc/wireguard/ \
  /etc/iscsi/ \
  /etc/samba/ \
  /etc/exports \
  /etc/systemd/system/nextcloud-sync.*

# Restore configuration
sudo tar xzf ~/dk-b-backup-YYYYMMDD.tar.gz -C /
sudo systemctl daemon-reload
```

### Clean Restart

```bash
# Stop all services
sudo systemctl stop smbd nmbd nfs-server nextcloud-sync.timer

# Unmount
sudo umount /mnt/external-nfs
sudo umount /mnt/iscsi

# Disconnect iSCSI
sudo iscsiadm -m node -u

# Stop WireGuard
sudo wg-quick down wg0

# Full restart
sudo reboot

# Or start services again
sudo ./scripts/start_services.sh
```

### Firewall

```bash
# Enable firewall
sudo ufw enable

# Allow services
sudo ufw allow 22/tcp          # SSH
sudo ufw allow 445/tcp         # Samba
sudo ufw allow 139/tcp         # Samba
sudo ufw allow 2049/tcp        # NFS
sudo ufw allow 111/tcp         # NFS
sudo ufw allow 51820/udp       # WireGuard

# Check status
sudo ufw status verbose

# Disable (not recommended)
sudo ufw disable
```

### Performance Tuning

```bash
# Check cache hit ratio
echo "scale=2; $(cat /sys/block/bcache0/bcache/stats_total/cache_hits) / \
  ($(cat /sys/block/bcache0/bcache/stats_total/cache_hits) + \
  $(cat /sys/block/bcache0/bcache/stats_total/cache_misses)) * 100" | bc

# Optimize writeback
echo 10 > /sys/block/bcache0/bcache/writeback_percent
echo 40 > /sys/block/bcache0/bcache/writeback_rate_minimum

# Sequential cutoff (skip cache for large files)
echo 8192 > /sys/block/bcache0/bcache/sequential_cutoff  # 8MB
```

## Common File Locations

```bash
# Configuration
/etc/dk-b-server.conf           # Main config
/etc/wireguard/wg0.conf         # WireGuard
/etc/samba/smb.conf             # Samba
/etc/exports                    # NFS
/etc/fstab                      # Mounts

# Logs
/var/log/dk-b-server/           # All DK-B logs
/var/log/samba/                 # Samba logs

# Scripts
./scripts/                      # All setup scripts

# Mount points
/mnt/iscsi                      # iSCSI storage
/mnt/external-nfs               # External NFS

# Systemd units
/etc/systemd/system/nextcloud-sync.service
/etc/systemd/system/nextcloud-sync.timer
/etc/systemd/system/mnt-external\x2dnfs.mount
```

## Emergency Commands

```bash
# Stop everything immediately
sudo systemctl stop smbd nmbd nfs-server
sudo umount -l /mnt/iscsi
sudo iscsiadm -m node -u

# Force unmount (use with caution)
sudo umount -f /mnt/iscsi
sudo umount -f /mnt/external-nfs

# Kill stuck processes
sudo pkill -9 smbd
sudo pkill -9 nfsd

# Reset iSCSI
sudo systemctl restart iscsid open-iscsi

# Clear cache (WARNING: DATA LOSS!)
# Only do this if you're sure
# echo 1 > /sys/block/bcache0/bcache/detach
```

## Useful Aliases

Add to ~/.bashrc:

```bash
# DK-B-Server aliases
alias dk-start='sudo /path/to/scripts/start_services.sh'
alias dk-status='sudo systemctl status smbd nmbd nfs-server'
alias dk-logs='sudo tail -f /var/log/dk-b-server/*.log'
alias dk-iscsi='sudo iscsiadm -m session'
alias dk-cache='cat /sys/block/bcache0/bcache/state'
alias dk-samba='sudo smbstatus'
alias dk-nfs='sudo exportfs -v'
```

## Quick Diagnostics

```bash
# One-line health check
echo "=== Network ===" && ping -c 1 8.8.8.8 && \
echo "=== iSCSI ===" && sudo iscsiadm -m session && \
echo "=== Mounts ===" && df -h | grep -E 'iscsi|nfs' && \
echo "=== Services ===" && systemctl is-active smbd nmbd nfs-server && \
echo "=== Cache ===" && cat /sys/block/bcache0/bcache/state

# Get summary
cat /var/log/dk-b-server/startup-summary.txt
```

For complete documentation, see [README.md](../README.md).
