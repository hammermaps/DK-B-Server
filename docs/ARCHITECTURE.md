# DK-B-Server Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     DK-B-Server System                      │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Network    │────▶│  WireGuard   │────▶│   Internet   │
│  Interface   │     │     VPN      │     │ / Remote Net │
└──────────────┘     └──────────────┘     └──────────────┘
       │
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                    iSCSI Connection                       │
│  Ubuntu Server ◀──────────▶ iSCSI Target (Network)      │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│                   Storage Stack                           │
│                                                           │
│  ┌────────────┐         ┌─────────────┐                 │
│  │iSCSI Device│◀───┬───▶│SSD Cache    │                 │
│  │ /dev/sdX   │    │    │ /dev/md128  │                 │
│  └────────────┘    │    └─────────────┘                 │
│        │           │                                      │
│        │       bcache                                     │
│        ▼           │                                      │
│  ┌────────────────┴──────────┐                          │
│  │   bcache Device           │                          │
│  │   /dev/bcache0            │                          │
│  │   (Cached iSCSI Storage)  │                          │
│  └───────────────────────────┘                          │
│        │                                                  │
│        ▼                                                  │
│  ┌───────────────────────────┐                          │
│  │   Filesystem (ext4/xfs)   │                          │
│  │   Mounted: /mnt/iscsi     │                          │
│  └───────────────────────────┘                          │
└──────────────────────────────────────────────────────────┘
       │
       ├──────────────┬──────────────┬─────────────┐
       ▼              ▼              ▼             ▼
┌────────────┐ ┌────────────┐ ┌───────────┐ ┌──────────┐
│   Samba    │ │    NFS     │ │ Nextcloud │ │  Local   │
│   Share    │ │   Export   │ │   Sync    │ │  Access  │
└────────────┘ └────────────┘ └───────────┘ └──────────┘
       │              │              │
       ▼              ▼              ▼
┌────────────────────────────────────────┐
│          Network Clients               │
│  Windows / Linux / macOS / Mobile      │
└────────────────────────────────────────┘
```

## Component Details

### 1. Network Layer

**Purpose**: Establish connectivity and VPN access

**Components**:
- Primary network interface (eth0/ens0)
- WireGuard VPN interface (wg0) - Optional
- Network validation and health checks

**Script**: `setup_network.sh`

### 2. Storage Layer

**Purpose**: Provide block-level storage via iSCSI

**Components**:
- iSCSI Initiator (open-iscsi)
- iSCSI Target (remote server)
- Network block device

**Flow**:
1. Discover iSCSI target
2. Login to target
3. Create block device (/dev/sdX)
4. Mount filesystem

**Script**: `setup_iscsi.sh`

### 3. Cache Layer

**Purpose**: Accelerate storage with SSD caching

**Components**:
- bcache kernel module
- Cache device: /dev/md128 (110GB SSD RAID)
- Backing device: iSCSI block device

**Cache Modes**:
- **writeback** (default): Best performance, uses RAM buffer
- **writethrough**: Safer, no write buffer
- **writearound**: Write directly to backing device

**Performance**:
- Cache hit rate: Typically 80-95% for workloads
- Latency reduction: 10-50x for cached reads
- Write buffering: Up to 16GB RAM utilization

**Script**: `setup_cache.sh`

### 4. File Sharing Layer

**Purpose**: Expose storage via network protocols

#### Samba (SMB/CIFS)
- **Protocol**: SMB2/SMB3
- **Clients**: Windows, macOS, Linux
- **Features**:
  - Guest access (configurable)
  - Optimized for performance
  - macOS compatibility (fruit VFS)

#### NFS (Network File System)
- **Protocol**: NFSv3, NFSv4, NFSv4.2
- **Clients**: Linux, macOS, Unix
- **Features**:
  - High performance
  - Low overhead
  - Native Unix permissions

**Script**: `setup_samba_nfs.sh`

### 5. External Storage Layer

**Purpose**: Mount remote NFS shares via VPN

**Components**:
- NFS client
- WireGuard VPN tunnel
- Systemd mount unit

**Use Cases**:
- Access remote backups
- Sync between sites
- Centralized storage access

**Script**: `mount_external_nfs.sh`

### 6. Synchronization Layer

**Purpose**: Automated Nextcloud synchronization

**Components**:
- Nextcloud client (nextcloudcmd)
- Systemd timer (5-minute interval)
- Sync script with error handling

**Features**:
- Automatic bidirectional sync
- Scheduled execution
- Comprehensive logging

**Script**: `setup_nextcloud_client.sh`

## Service Dependencies

```
Network (Mandatory)
   │
   ├─▶ WireGuard VPN (Optional)
   │      │
   │      └─▶ External NFS (Optional)
   │
   └─▶ iSCSI Storage (Mandatory)
          │
          └─▶ bcache Cache (Mandatory)
                 │
                 ├─▶ Samba Server (Mandatory)
                 │
                 ├─▶ NFS Server (Mandatory)
                 │
                 └─▶ Nextcloud Sync (Optional)
```

## Startup Sequence

The `start_services.sh` script orchestrates startup in this order:

1. **Network** (5s delay)
   - Check connectivity
   - Start WireGuard if enabled
   
2. **iSCSI** (5s delay)
   - Install packages
   - Discover target
   - Login and mount
   
3. **Cache** (5s delay)
   - Install bcache
   - Format cache device
   - Attach to backing device
   
4. **File Sharing** (5s delay)
   - Configure Samba
   - Configure NFS
   - Start services
   
5. **External NFS** (5s delay)
   - Verify VPN
   - Mount remote share
   
6. **Nextcloud** (0s delay)
   - Install client
   - Setup sync timer

## Data Flow

### Read Operation
```
Client Request
    │
    ▼
Samba/NFS Server
    │
    ▼
Filesystem Cache (Kernel)
    │
    ▼
bcache Layer ────────┐
    │                │
    ├─ Cache Hit ────┤
    │   (SSD)        │
    │                │
    └─ Cache Miss    │
         │           │
         ▼           │
    iSCSI Device     │
         │           │
         ▼           │
    Network ◀────────┘
         │
         ▼
    iSCSI Target
```

### Write Operation (Writeback Mode)
```
Client Request
    │
    ▼
Samba/NFS Server
    │
    ▼
Filesystem
    │
    ▼
bcache Layer
    │
    ├─▶ RAM Buffer (16GB available)
    │       │
    │       ▼
    │   SSD Cache (/dev/md128)
    │       │
    │       ▼
    │   Async Write to backing device
    │       │
    │       ▼
    └─▶ iSCSI Device
            │
            ▼
        Network
            │
            ▼
        iSCSI Target
```

## Resource Utilization

### CPU
- Minimal overhead
- iSCSI: ~1-2% per 100MB/s
- bcache: ~2-3% overhead
- Samba/NFS: ~5-10% per 100MB/s

### Memory
- Base system: ~500MB
- bcache writeback buffer: Up to 16GB
- Samba: ~50MB + ~10MB per connection
- NFS: ~30MB + ~5MB per connection
- Total recommended: 16GB

### Disk I/O
- SSD Cache: Random I/O optimized
- iSCSI: Sequential and random
- Typical cache hit rate: 80-95%

### Network
- iSCSI: Up to line speed
- Samba: Up to line speed
- NFS: Up to line speed
- WireGuard: Minimal overhead (<5%)

## Security Architecture

```
┌─────────────────────────────────────────┐
│          Security Layers                │
└─────────────────────────────────────────┘

Network Level:
├─ Firewall (UFW)
│  ├─ Block all by default
│  ├─ Allow Samba (445)
│  ├─ Allow NFS (2049)
│  └─ Allow WireGuard (51820)
│
├─ WireGuard VPN
│  ├─ Encrypted tunnel
│  ├─ Key-based auth
│  └─ Network isolation
│
Storage Level:
├─ iSCSI
│  ├─ CHAP authentication (optional)
│  ├─ Network ACL
│  └─ Initiator authentication
│
Application Level:
├─ Samba
│  ├─ User authentication
│  ├─ Share permissions
│  └─ Guest access control
│
├─ NFS
│  ├─ Network ACL
│  ├─ Export restrictions
│  └─ Root squash
│
└─ Nextcloud
   ├─ HTTPS only
   ├─ App passwords
   └─ Credential storage
```

## Logging Architecture

```
/var/log/dk-b-server/
├── common.log              # Shared functions
├── setup_network.log       # Network setup
├── setup_iscsi.log         # iSCSI configuration
├── setup_cache.log         # Cache setup
├── setup_samba_nfs.log     # File sharing
├── mount_external_nfs.log  # External mounts
├── setup_nextcloud_client.log  # Nextcloud setup
├── nextcloud-sync.log      # Sync operations
├── start_services.log      # Main orchestration
└── startup-summary.txt     # System status report
```

## Configuration Management

```
/etc/dk-b-server.conf       # Main configuration
/etc/wireguard/wg0.conf     # WireGuard config
/etc/iscsi/initiatorname.iscsi  # iSCSI initiator
/etc/iscsi/iscsid.conf      # iSCSI daemon
/etc/samba/smb.conf         # Samba config
/etc/exports                # NFS exports
/etc/fstab                  # Filesystem mounts
/etc/systemd/system/        # Service units
```

## Monitoring Points

Key metrics to monitor:

1. **Network**: Bandwidth, latency, packet loss
2. **iSCSI**: Session status, I/O errors, latency
3. **Cache**: Hit rate, dirty data, eviction rate
4. **Samba**: Active connections, throughput
5. **NFS**: Active mounts, operation latency
6. **System**: CPU, RAM, disk I/O

Recommended tools:
- `iostat` - Disk I/O statistics
- `iftop` - Network monitoring
- `smbstatus` - Samba connections
- `nfsstat` - NFS statistics
- `bcache-status` - Cache statistics

For more information, see [README.md](../README.md) and [INSTALLATION.md](INSTALLATION.md).
