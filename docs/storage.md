# Storage

## Purpose

The storage system provides persistent storage for applications and user data, local storage for the virtualization layer, and a separate location for virtual machine and container backups.

The design separates:

* Proxmox's local virtualization storage
* Persistent application data
* User-owned data
* Virtual machine and container backups

Data protection is provided through ZFS snapshots, encrypted Proxmox Backup Server (PBS) backups, and independently retained OPNsense configuration exports.

## Storage Architecture

### Node A — Proxmox

Node A contains a 256 GB SSD divided between two Proxmox storage volumes:

* **`local` — approximately 42 GB**

  * ISO images
  * LXC container templates
* **`local-lvm` — approximately 180 GB**

  * Virtual machine disks
  * LXC container disks

Node A does not serve as the primary long-term storage location for application or user data.

### Node B — TrueNAS

Node B provides the system's persistent network storage through two independent ZFS pools.

#### `tank` — approximately 2 TB

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

It is exposed to Node A over NFS and is accessible from the Proxmox host and Docker VM. Applications use this dataset for persistent data regardless of its specific content, avoiding a large number of narrowly scoped NAS datasets.

Examples include documents, pictures, games, media, and other data consumed by applications.

`tank/data` is protected by hourly ZFS snapshots with a one-month retention period.

##### `tank/users`

Each user has an independently defined ZFS dataset under `tank/users`.

Per-user datasets allow storage quotas and permissions to be managed independently. User datasets are exposed through SMB for personal file shares.

User data is protected by hourly ZFS snapshots with a one-month retention period.

#### `backup` — approximately 0.5 TB

The `backup` pool is dedicated to Proxmox guest backups.

```text
backup/
└── vm-backups/
```

The pool hosts the PBS datastore used for scheduled Proxmox backups. Keeping this pool separate from `tank` separates guest backup storage from primary application and user data at the pool level.

The `backup` pool is protected by ZFS snapshots with a 12-hour schedule and two-week retention.

### Code and Repository Storage

The NFS data storage also provides durable storage for infrastructure source code and Git repositories.

```text
code/
├── repos/       # Forgejo Git repositories
└── source/      # Working copy of all homelab Infrastructure as Code
```

Forgejo repositories are stored on NFS because repository history is durable infrastructure data that should survive failure or replacement of the Node A runtime.

Working copies are also stored on NFS so that the source tree remains independent of the local runtime filesystem.

The public infrastructure repository contains version-controlled deployment and infrastructure configuration. Private configuration and secrets are maintained separately and are not committed to the public repository.

The working tree and live deployment configuration are managed as part of the repository-based deployment workflow rather than relying on an unrelated `/opt/docker` directory.

Repository storage on NFS provides persistence, but does not by itself constitute an independent backup. Git history, ZFS snapshots, and PBS backups protect against different failure scenarios.

## Data Protection

The storage system uses several complementary protection mechanisms.

### ZFS Snapshots

Snapshots provide short- and medium-term recovery from logical problems such as:

* Accidental deletion
* Unwanted modifications
* Application mistakes
* Configuration mistakes
* Other changes that do not require restoration of an entire virtual machine

Current snapshot policies are:

| Dataset        | Frequency      | Retention |
| -------------- | -------------- | --------- |
| `tank/data`    | Hourly         | 1 month   |
| `tank/users/*` | Hourly         | 1 month   |
| `backup`       | Every 12 hours | 2 weeks   |

Snapshots are considered **data protection, not a substitute for independent backups**. They preserve previous filesystem states within the same storage system.

### Proxmox Backup Server

PBS provides recoverable copies of virtual machine and container workloads.

The automated backup job runs daily at 04:00 and stores backups on the `backup` pool on Node B.

The Docker VM and standalone LXCs, including Jellyfin, are included in the backup process.

#### Encryption

PBS backups are encrypted client-side before backup data is transferred to the datastore.

The encryption key is managed through Bitwarden, which serves as the central credential and key store. The key must remain available for encrypted backup recovery.

The configured encryption key is compatible with Proxmox VE's automated PBS backup integration.

Encryption protects backup contents, but does not replace retention, verification, or recovery testing.

#### Retention and Maintenance

PBS retention is configured with the following policies:

| Policy       |          Retention |
| ------------ | -----------------: |
| Keep last    |          7 backups |
| Keep daily   |    7 daily backups |
| Keep weekly  |   4 weekly backups |
| Keep monthly | 12 monthly backups |
| Keep yearly  |  10 yearly backups |

These rules overlap, so the number of retained restore points is not necessarily the sum of all policy values.

Automated pruning removes restore points that are no longer required by the retention policy. Garbage collection subsequently reclaims datastore chunks that are no longer referenced by retained backups.

Backup verification is scheduled to check stored backup data for integrity. Verification, pruning, and garbage collection serve different purposes and are configured as separate maintenance operations.

#### Restore Testing

Recovery has been tested at both the file and guest levels:

* **File Restore:** Individual files and configuration files can be browsed and retrieved from a backup.
* **Full Restore:** An encrypted Jellyfin LXC backup was successfully restored under a new container ID.

The successful full restore demonstrates that the configured encryption key and backup workflow can recover a complete container.

The restored guest should be checked for dependencies that may not be included in its backup, such as external NFS mounts and other network services.

Restore testing provides evidence of recoverability; successful backup jobs alone do not establish that a workload can be restored successfully.

### OPNsense Configuration Backups

OPNsense is deliberately excluded from the regular guest backup process. Backing up the router VM through a snapshot-based process can interrupt its operation and disrupt the network on which the rest of the infrastructure depends.

Instead, OPNsense configuration XML exports are maintained separately in two locations:

* The personal SMB share on TrueNAS
* The user's laptop

These copies provide a recovery path for router configuration without requiring a full VM snapshot.

Configuration exports are sensitive and must be protected accordingly. Their recovery procedure should remain documented and the exports should be kept reasonably current.

## Recovery Boundaries

The current system is designed primarily for recovery from logical errors and failures of the virtualization layer.

Examples include:

* **Accidental data deletion:** Recover eligible data from ZFS snapshots.
* **Unwanted application changes:** Recover previous application data from snapshots where applicable.
* **Broken Docker VM:** Restore the VM from a PBS backup.
* **Failed standalone LXC:** Restore the container from a PBS backup.
* **Accidental file deletion:** Retrieve individual files through PBS File Restore or ZFS snapshots, depending on the data and recovery point required.
* **Lost OPNsense configuration:** Restore an exported configuration from the SMB share or laptop.

The current design does **not** provide independent off-host or off-site disaster recovery for Node B's storage pools.

The primary datasets, their snapshots, and the Proxmox backups ultimately reside on the same TrueNAS system. A failure affecting that system could therefore compromise multiple recovery mechanisms at once.

This is an intentional limitation of the current homelab design rather than an attempt to provide enterprise-grade disaster recovery.

## Design Principles

The storage architecture favors a small number of broadly scoped datasets over extensive dataset fragmentation.

Application data is consolidated into `tank/data`, while user data is separated into per-user datasets where quotas and permissions provide a concrete reason for the separation.

Storage protection is layered:

```text
Primary application and user data
    |
    ├── ZFS snapshots
    |      └── Recovery from logical mistakes
    |
    └── Network-accessible storage
           └── Persistent data independent of Node A's local SSD

Virtualized workloads
    |
    └── Encrypted PBS backups
           ├── Scheduled backup jobs
           ├── Retention and pruning
           ├── Verification and garbage collection
           └── File-level and full-guest recovery

OPNsense
    |
    └── Configuration XML exports
           ├── TrueNAS SMB share
           └── Personal laptop
```

The design prioritizes straightforward administration, recoverability, and separation between runtime infrastructure and persistent data.

It can be expanded later with additional replication or off-site backup mechanisms if the system's recovery requirements increase.
