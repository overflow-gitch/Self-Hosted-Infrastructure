# Storage

## Purpose

The storage system provides persistent storage for applications and user data, local storage for the virtualization layer, and a separate location for virtual machine and container backups.

The design separates:

* Proxmox's local virtualization storage
* Persistent application data
* User-owned data
* Virtual machine and container backups

Data protection is provided primarily through ZFS snapshots and Proxmox backups.

## Storage Architecture

### Node A — Proxmox

Node A contains a 256 GB SSD divided between two Proxmox storage volumes:

* **`local` — ~42 GB**

  * ISO images
  * LXC container templates
* **`local-lvm` — ~180 GB**

  * Virtual machine disks
  * LXC container disks

Node A does not serve as the primary long-term storage location for application or user data.

### Node B — TrueNAS

Node B provides the system's persistent network storage through two independent ZFS pools.

#### `tank` — ~2 TB

`tank` contains the primary persistent data used by applications and users.

```text
tank/
├── data/
└── users/
    ├── <user>
    ├── <user>
    └── ...
```

##### `tank/data`

`data` is the general-purpose application data store.

It is exposed to Node A over NFS and is accessible both:

* from the Proxmox host
* from the Docker VM

Applications use this dataset for persistent data regardless of its specific content. This intentionally avoids maintaining a large number of separate NAS datasets for different application data types.

Examples include documents, pictures, games, media, and other data consumed by applications.

`tank/data` is protected by hourly ZFS snapshots with a one-month retention period.

##### `tank/users`

Each user has an independently defined ZFS dataset under `tank/users`.

Per-user datasets allow storage quotas and permissions to be managed independently.

User datasets are exposed through SMB for personal file shares.

User data is protected by hourly ZFS snapshots with a one-month retention period.

#### `backup` — ~0.5 TB

The `backup` pool is dedicated to Proxmox guest backups.

```text
backup/
└── vm-backups/
```

Proxmox automatically creates backups at 04:00 for:

* the Docker VM
* standalone LXCs, such as Jellyfin

The backup dataset is separate from the primary application and user data stored in `tank`.

The `backup` pool is protected by ZFS snapshots with a 12-hour schedule and two-week retention.

## Data Protection

The storage system uses two complementary forms of protection.

### ZFS Snapshots

Snapshots provide short- and medium-term recovery from logical problems such as:

* accidental deletion
* unwanted modifications
* application mistakes
* configuration mistakes
* other changes that do not require restoration of an entire virtual machine

Current snapshot policies are:

| Dataset        |      Frequency | Retention |
| -------------- | -------------: | --------: |
| `tank/data`    |         Hourly |   1 month |
| `tank/users/*` |         Hourly |   1 month |
| `backup`       | Every 12 hours |   2 weeks |

Snapshots are considered **data protection**, rather than a substitute for independent backups. They preserve previous filesystem states within the same storage system.

### Proxmox Backups

Proxmox backups provide recoverable copies of virtual machine and container workloads.

The automated backup job runs at 04:00 and stores backups on the separate `backup` pool on Node B.

The Docker VM and standalone LXCs are included in this process.

OPNsense is deliberately excluded. Performing a full VM backup of the router interferes with its operation and can interrupt the network on which the rest of the infrastructure depends.

Instead, the OPNsense configuration is backed up separately.

## Recovery Boundaries

The current system is designed primarily for recovery from logical errors and failures of the virtualization layer.

Examples include:

* **Accidental data deletion:** recover from ZFS snapshots.
* **Unwanted application changes:** recover application data from snapshots.
* **Broken Docker VM:** restore the VM from a Proxmox backup.
* **Failed standalone LXC:** restore the container from its Proxmox backup.
* **Lost OPNsense configuration:** restore its configuration backup.

The current design does **not** provide independent off-host or off-site disaster recovery for Node B. The primary datasets, their snapshots, and the Proxmox backups ultimately reside on the same TrueNAS system.

This is an intentional limitation of the current homelab design rather than an attempt to provide enterprise-grade disaster recovery.

## Design Principles

The storage architecture favors a small number of broadly scoped datasets over extensive dataset fragmentation.

Application data is therefore consolidated into `tank/data`, while user data is separated into per-user datasets where quotas and permissions provide a concrete reason for the separation.

Storage protection is layered:

```text
Primary data
    │
    ├── ZFS snapshots
    │      └── recovery from logical mistakes
    │
    └── Proxmox backups
           └── recovery of virtualized workloads
```

The design can be expanded later with additional replication or off-site backup mechanisms if the system's recovery requirements increase.
