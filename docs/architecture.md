# Architecture

## Overview

This homelab is a small self-hosted infrastructure environment built around two physically separate nodes.

The architecture separates **compute and network infrastructure** from **persistent storage**:

* **Node A** provides compute, virtualization, and network-edge services.
* **Node B** provides persistent storage and backup storage.
* **Proxmox VE** provides the virtualization layer on Node A.
* **OPNsense** provides routing, firewalling, DNS, and VPN access.
* A dedicated **Docker VM** hosts application and infrastructure services.
* **TrueNAS** provides centralized storage through ZFS, NFS, and SMB.

The following diagrams describe the system from physical hardware through the network and storage layers to the applications running on top of them.

---

## Goals

The architecture is designed around several principles:

* Separate persistent storage from compute infrastructure.
* Centralize network routing and security.
* Isolate infrastructure roles where practical.
* Keep application workloads separate from the hypervisor.
* Minimize unnecessary external exposure.
* Make efficient use of limited hardware.
* Keep the architecture simple enough to understand and maintain.

---

# Complete Architecture

Arrows point from dependencies to dependent system.

```mermaid
flowchart TB
    subgraph Physical["Physical Layer"]
        A["Node A — M920q"]
        B["Node B — TC-220"]
    end

    subgraph Infrastructure["Infrastructure Layer"]
        PVE["Proxmox VE"]
        TN["TrueNAS"]
    end

    subgraph Network["Network Layer"]
        OPN["OPNsense"]
        DNS["Unbound DNS"]
        VPN["WireGuard VPN"]
    end

    subgraph Storage["Storage Layer"]
        SHARES["NFS/SMB shares"]
        DATA["ZFS Datasets"]
        BACKUPS["Backups"]
    end

    subgraph Runtime["Container Runtime Layer"]
        DOCKER["Docker VM"]
        COMPOSE["Docker Compose"]
        LXC
    end

    subgraph Services["Core Services"]
        TRAEFIK["Traefik"]
        AUTH["Authentik"]
        PG["PostgreSQL"]
        REDIS["Redis"]
        MON["Prometheus / Loki"]
    end

    subgraph Applications["Application Layer"]
            subgraph DC["Docker Containers"]
            FORGEJO["Forgejo"]
            IMMICH["Immich"]
            PAPERLESS["Paperless-ngx"]
        end
        subgraph LXCC["LXC Instances"]
            JELLY["Jellyfin"]
        end
    end

    A --> PVE
    B --> TN

    PVE --> OPN
    OPN --> DNS
    OPN --> VPN

    PVE --> Runtime
    DOCKER --> COMPOSE

    TN --> Storage

    Network --> Runtime
    Network --> Infrastructure
    Storage --> Runtime
    Storage --> PVE

    Runtime --> Services
    Services --> Applications
```

The architecture follows a relatively simple progression:

**Hardware → Infrastructure → Network / Storage → Virtualization → Runtime → Applications**

Each layer provides the foundation for the layer above it while remaining as independent as practical.

The network stack is dependent on the infrastructure layer, but also is necessary for the infrastructure layer's connectivity.

The storage layer must be consumed by the PVE host due to unprivileged LXCs not being able to mount network shares. 

---

# Hardware

The physical infrastructure consists of two refurbished desktop systems with deliberately different roles.

```mermaid
flowchart TB
    subgraph NodeA["Node A — Lenovo M920q"]
        ACPU["Intel i5-8500T<br/>6C / 6T"]
        ARAM["16 GB DDR4"]
        ASSD["256 GB SSD"]
        ANIC["4× 2.5 GbE NIC<br/>passed through to OPNsense"]
    end

    subgraph NodeB["Node B — Acer TC-220"]
        BCPU["AMD A10-7800<br/>4C / 4T"]
        BRAM["16 GB DDR3"]
        BSSD["80 GB SSD<br/>boot / OS"]
        BTANK["2 TB HDD<br/>ZFS tank"]
        BBACKUP["512 GB HDD<br/>backup storage"]
    end

    NodeA -->|"Compute / virtualization / network edge"| AROLE["Proxmox host"]
    NodeB -->|"Persistent storage / backups"| BROle["TrueNAS host"]
```

Node A concentrates compute, virtualization, and network-edge functions because its compact form factor and relatively stronger CPU make it better suited to those workloads.

Node B is dedicated primarily to storage because its larger chassis and number of SATA ports provides substantially greater internal drive capacity.

Detailed hardware specifications are documented in [hardware.md](hardware.md)

---

# Infrastructure

The physical hardware provides two distinct infrastructure domains:

```mermaid
flowchart TB
    subgraph Physical["Physical Infrastructure"]
        subgraph A["Node A"]
            PVE["Proxmox VE"]
        end

        subgraph B["Node B"]
            TN["TrueNAS"]
        end
    end

    PVE -->|"Virtualization"| VM["Virtual Machines / Containers"]
    TN -->|"Persistent storage"| DATA["Datasets / Shares / Backups"]
```

Node A provides the compute platform on which the network edge and application runtime operate.

Node B provides storage independently of the compute platform.

This separation means that storage does not need to be tied to the lifecycle of a particular virtual machine or application host.

---

# Network

OPNsense operates as the network edge of the homelab behind the ISP gateway. Arrows denote traffic within the homelab.

```mermaid
graph TD
    Internet --> Modem["ISP Gateway / Router (Double NAT)"]
    subgraph ISP-Contolled network
        Modem --> WiFi["ISP Wireless AP (unconfigurable)"]
        WiFi --> WirelessClients["Wireless Clients"]
        WirelessClients --> VPN["WireGuard VPN Tunnel via OPNsense"]
    end

    Modem <--> OPNsense["OPNsense VM - Routing / Firewall / VPN"]
    OPNsense <--> LAN["LAN Segment - Flat Layer 2"]
    subgraph homelab-controlled network
        LAN <--> Proxmox["Proxmox VE Host (Lenovo M920q)"]
        LAN <--> TrueNAS["TrueNAS (Acer TC-220)"]
        LAN <--> WiredClients["Wired Clients"]

        LAN <--> Docker["Docker Guest (Debian)"]    
    end
    VPN --> OPNsense
```

OPNsense provides:

* Routing
* Firewalling
* DHCP
* DNS through Unbound
* WireGuard VPN access
* Layer 3 network segmentation (VLANs)

The current physical network does not include a managed switch, so Layer 2 VLAN isolation is not currently available. Multiple IP subnets provide logical Layer 3 separation where required.

The ISP wireless network remains outside the homelab network.

Detailed addressing, firewall, DNS, and VPN configuration belongs in [`networking.md`](networking.md).

---

# Storage

Persistent storage is physically separated from the compute infrastructure. Arrows denote storage transfers.

```mermaid
flowchart
    subgraph NodeA["Node A — Compute"]
        DOCKER["Docker VM"]
        PVE["Proxmox VE"]
        LXC
    end

    subgraph NodeB["Node B — Storage"]
        TN["TrueNAS"]
        ZFS["ZFS Storage/Datasets"]
        BACKUP["Backup Storage"]

        TN --> ZFS
        ZFS --> SHARES["SMB/NFS Shares"]

        ZFS --> BACKUP
    end

    NodeB --> |"Network Mounts"| NodeA
    NodeA <--> |"Backup & Restore"| NodeB

    PVE --> DOCKER
    PVE --> LXC
```

TrueNAS provides the central persistent-storage layer through ZFS, SMB, and NFS.

The storage layer is independent of the Docker runtime. Applications may consume storage from TrueNAS without making the Docker VM itself the authoritative location of the underlying data.

This distinction separates:

* **Configuration** — version-controlled with Git
* **Application runtime/state** — maintained by the application environment
* **Persistent user data** — stored on TrueNAS where appropriate
* **Backups** — stored independently from the application runtime

Detailed datasets, shares, snapshots, and persistence boundaries belong in [`storage.md`](storage.md).

---

# Virtualization

Proxmox VE provides the virtualization layer on Node A. Arrows point from dependencies to dependent system.

```mermaid
flowchart TB
    HW["Node A Hardware"]
    PVE["Proxmox VE"]

    subgraph Guests["Virtualized Workloads"]
        OPN["OPNsense VM"]
        DOCKER["Docker VM"]
        LXC["LXCs"]
        OTHER["Other VMs / LXCs"]
    end

    HW --> PVE

    PVE --> OPN
    PVE --> DOCKER
    PVE --> LXC
    PVE --> OTHER
```

OPNsense serves as the dedicated router, firewall and VPN for this infrastructure stack.

The Docker VM is the primary method of setting up the application layer.

Linux Containers (LXC) are used when a service requires capabilities that the Docker VM cannot satisfy. An example would be an application like Jellyfin, which requires GPU access.

Detailed VM, LXC, passthrough, and virtual-network configuration belongs in [`virtualization.md`](virtualization.md).

---

# Applications

Applications run primarily through Docker Compose inside the Docker VM. Arrows point from dependencies to dependent system.

```mermaid
flowchart LR
    subgraph VM["Docker VM"]
        subgraph INFRA["Infrastrucutre"]
        TRAEFIK["Traefik<br/>Reverse Proxy"]
        AUTH["Authentik<br/>Authentication"]
        PG["PostgreSQL<br/>Database"]
        REDIS["Redis<br/>Cache"]
        MON["Prometheus / Loki<br/>Monitoring & Logging"]
        end
        subgraph Apps["Applications"]
            FORGEJO["Forgejo"]
            IMMICH["Immich"]
            OTHER["Other Applications"]
        end
    end
    subgraph LXC
        JELLY["Jellyfin LXC"]
    end 
    INFRA --> JELLY
    INFRA --> Apps
```

The application layer is divided into two broad categories:

### Infrastructure Services

Shared services that provide capabilities to applications:

* **Traefik** — reverse proxy
* **Authentik** — authentication and SSO
* **PostgreSQL** — database infrastructure
* **Redis** — caching and transient application data
* **Prometheus / Loki** — monitoring and logging

These services are dependencies to other applications.

### Applications

All services that are not dependencies are under this category.

Applications should use the existing infrastructure where practical rather than introducing duplicate networking, authentication, database, or storage infrastructure for each service.


