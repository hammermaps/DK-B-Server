# Installation Guide

## Prerequisites

Before installing DK-B-Server automation scripts, ensure you have:

1. **Ubuntu Server 24.04 LTS** freshly installed
2. **Root access** or sudo privileges
3. **Network connectivity** configured
4. **iSCSI target** available on your network
5. **SSD RAID array** (/dev/md128) configured and available

## Step-by-Step Installation

### Step 1: System Update

```bash
sudo apt update
sudo apt upgrade -y
sudo reboot
```

### Step 2: Clone Repository

```bash
# Install git if not present
sudo apt install -y git

# Clone the repository
git clone https://github.com/hammermaps/DK-B-Server.git
cd DK-B-Server
```

### Step 3: Prepare Configuration

```bash
# Copy example configuration
sudo cp config/dk-b-server.conf.example /etc/dk-b-server.conf

# Set secure permissions
sudo chmod 600 /etc/dk-b-server.conf

# Edit configuration
sudo nano /etc/dk-b-server.conf
```

#### Required Configuration

At minimum, configure these essential settings:

```bash
# iSCSI Target (REQUIRED)
ISCSI_TARGET_PORTAL="YOUR_ISCSI_IP:3260"
ISCSI_TARGET_IQN="iqn.YYYY-MM.com.example:target"
```

#### Optional: WireGuard VPN

If you need WireGuard for external NFS access:

```bash
# Create WireGuard configuration
sudo mkdir -p /etc/wireguard
sudo nano /etc/wireguard/wg0.conf
```

Example WireGuard configuration:
```ini
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.0.0.2/24

[Peer]
PublicKey = PEER_PUBLIC_KEY
Endpoint = vpn.example.com:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

Enable in config:
```bash
ENABLE_WIREGUARD="yes"
```

#### Optional: External NFS

If you want to mount external NFS:

```bash
ENABLE_EXTERNAL_NFS="yes"
EXTERNAL_NFS_SERVER="10.0.0.5"
EXTERNAL_NFS_EXPORT="/srv/shared"
```

#### Optional: Nextcloud Sync

If you want automated Nextcloud synchronization:

```bash
ENABLE_NEXTCLOUD="yes"
NEXTCLOUD_SERVER_URL="https://nextcloud.example.com"
NEXTCLOUD_USER="your-username"
NEXTCLOUD_PASSWORD="your-app-password"
```

### Step 4: Verify Cache Device

Ensure your SSD RAID array is available:

```bash
# Check if device exists
ls -l /dev/md128

# Check device information
sudo mdadm --detail /dev/md128
```

### Step 5: Run Installation

```bash
# Make sure scripts are executable
chmod +x scripts/*.sh

# Run the main setup script
sudo ./scripts/start_services.sh
```

The script will:
1. ✓ Initialize network
2. ✓ Setup WireGuard (if enabled)
3. ✓ Connect to iSCSI target
4. ✓ Mount iSCSI storage
5. ✓ Configure SSD cache
6. ✓ Setup Samba & NFS
7. ✓ Mount external NFS (if enabled)
8. ✓ Setup Nextcloud sync (if enabled)

### Step 6: Verify Installation

```bash
# Check all services
sudo systemctl status smbd nmbd nfs-server

# Check iSCSI session
sudo iscsiadm -m session

# Check mounts
df -h | grep -E "(iscsi|nfs|bcache)"

# Check logs
ls -lh /var/log/dk-b-server/
```

## Post-Installation

### Access Your Shares

#### Samba (Windows/macOS/Linux)
```bash
# Windows
\\YOUR-SERVER-IP\iscsi-storage

# macOS Finder
smb://YOUR-SERVER-IP/iscsi-storage

# Linux
sudo mount -t cifs //YOUR-SERVER-IP/iscsi-storage /mnt/share
```

#### NFS (Linux/macOS)
```bash
# Linux
sudo mount -t nfs YOUR-SERVER-IP:/mnt/iscsi /mnt/share

# macOS
sudo mount -t nfs YOUR-SERVER-IP:/mnt/iscsi /mnt/share
```

### Enable Firewall (Recommended)

```bash
# Enable UFW
sudo ufw enable

# Allow SSH
sudo ufw allow 22/tcp

# Allow Samba
sudo ufw allow 445/tcp
sudo ufw allow 139/tcp

# Allow NFS
sudo ufw allow 2049/tcp
sudo ufw allow 111/tcp

# Allow WireGuard (if used)
sudo ufw allow 51820/udp

# Check status
sudo ufw status
```

### Setup Automatic Startup

The scripts automatically configure services to start on boot. Verify:

```bash
sudo systemctl is-enabled smbd nmbd nfs-server open-iscsi

# For WireGuard
sudo systemctl is-enabled wg-quick@wg0

# For Nextcloud sync
sudo systemctl is-enabled nextcloud-sync.timer
```

## Troubleshooting Installation

### Problem: Script fails at network step

```bash
# Check network connectivity
ping -c 3 8.8.8.8

# Check DNS
nslookup google.com

# Restart networking
sudo systemctl restart systemd-networkd
```

### Problem: Cannot find iSCSI target

```bash
# Test connectivity to iSCSI server
ping YOUR_ISCSI_IP

# Try manual discovery
sudo iscsiadm -m discovery -t st -p YOUR_ISCSI_IP:3260

# Check firewall on iSCSI server (port 3260)
```

### Problem: Cache device not found

```bash
# Check if RAID array exists
cat /proc/mdstat

# If RAID needs to be assembled
sudo mdadm --assemble --scan

# Verify device
sudo mdadm --detail /dev/md128
```

### Problem: Permission denied errors

```bash
# Ensure running as root
sudo -i

# Check script permissions
ls -la scripts/

# Make executable
chmod +x scripts/*.sh
```

## Uninstallation

If you need to remove the setup:

```bash
# Stop all services
sudo systemctl stop smbd nmbd nfs-server nextcloud-sync.timer

# Disable services
sudo systemctl disable smbd nmbd nfs-server nextcloud-sync.timer

# Unmount filesystems
sudo umount /mnt/iscsi
sudo umount /mnt/external-nfs

# Logout from iSCSI
sudo iscsiadm -m node -u

# Remove bcache (WARNING: This will remove cache!)
# Only do this if you want to completely remove cache setup
# sudo wipefs -a /dev/md128

# Remove configuration
sudo rm /etc/dk-b-server.conf

# Remove logs
sudo rm -rf /var/log/dk-b-server/

# Remove systemd units
sudo rm /etc/systemd/system/nextcloud-sync.*
sudo systemctl daemon-reload
```

## Next Steps

After successful installation:

1. **Test file access**: Try accessing Samba and NFS shares
2. **Monitor performance**: Check cache statistics and system resources
3. **Setup monitoring**: Consider Prometheus, Grafana, or Netdata
4. **Configure backups**: Setup regular backups of your data
5. **Review security**: Ensure firewall rules and access controls are appropriate

For more details, see the main [README.md](../README.md).
