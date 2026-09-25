# Services

The application layer provides the services used by the homelab's users and ties them into shared infrastructure for networking, authentication, data storage, caching, and observability.

Most services run as Docker Compose applications on the Docker VM. Jellyfin is the exception: it runs in its own LXC because it requires more direct access to hardware than the Docker-based application environment currently provides.

The services are intended primarily for personal use by the owner, friends, and family. All services are restricted to the LAN or VPN; none are intended to be directly exposed to the public Internet.

## Service Deployment

Docker Compose is the standard deployment method.

Each application is maintained independently under:

```text
/opt/docker/service/<service>/
├── .env
├── compose.yml
└── <application data>
```

Application data consumed by a service is kept separate from the application's local configuration when appropriate. Shared user data is provided through the NFS storage layer rather than being embedded into individual containers.

Compose is used because its declarative configuration makes the application environment reproducible and easy to maintain at the individual-service level. It also allows application-specific Traefik configuration to be maintained alongside the application that uses it.

Container management and updates are currently performed manually.

LXC is used as an exception when Docker or a conventional VM cannot provide the required access to hardware or other resources. Jellyfin currently uses this deployment method.

## Services

### Application Services

The current application environment includes:

* **Jellyfin** — media streaming and playback. Runs separately from the Docker environment in an LXC.
* **Navidrome** — music streaming and library management.
* **ROMM** — game-library management.
* **Homepage** — application dashboard.
* **Vaultwarden** — password-management service. Currently deployed but not actively used.


### Shared Infrastructure Services

Several services exist primarily to support other applications rather than to provide an end-user function themselves.

#### Traefik

Traefik provides reverse-proxying for services with web interfaces.

Applications that expose interfaces generally connect to Traefik rather than being individually exposed. This provides a common entry point for application access and allows routing configuration to remain associated with each application's Compose deployment.

Traefik is therefore a central dependency of the application layer: if it becomes unavailable, applications may continue running but their interfaces will generally no longer be accessible.

#### Authentik

Authentik provides centralized authentication where applications can support it.

The current implementation primarily uses Authentik through Traefik forward authentication rather than requiring every application to implement a compatible identity protocol itself.

Not every application uses Authentik. In particular, some applications have limitations that make centralized authentication impractical:

* Navidrome has client-specific authentication limitations, particularly for mobile use.
* Jellyfin does not currently provide a suitable authentication integration for the desired setup.

These applications retain their own authentication mechanisms rather than being forced into the common SSO path.

#### PostgreSQL

PostgreSQL provides shared relational database infrastructure for applications that require it.

Rather than deploying a separate database server for every application, applications that support the shared PostgreSQL environment use the common database service.

PostgreSQL is therefore part of the shared application infrastructure rather than an application itself.

#### Redis

Redis provides shared caching and related transient data services for applications that require it.

Like PostgreSQL, Redis is centralized so that compatible applications can use a common infrastructure service rather than maintaining independent Redis instances.

#### Monitoring and Logging

The monitoring environment consists of:

* Grafana
* Prometheus
* Loki
* Promtail
* Proxmox VE exporter

The monitoring stack is intended to provide metrics, dashboards, and centralized logs across the environment.

It is currently incomplete and is not yet relied upon as a functional dependency by the application layer. Service operation does not depend on logs being available.

This distinction is intentional: observability is treated as important infrastructure, but a monitoring failure should not itself bring application services down.

## Shared Service Relationships

Applications generally fit into a common dependency pattern:

```text
Application
    │
    ├──→ Traefik
    │       └──→ Authentik (where supported)
    │
    ├──→ PostgreSQL (where required)
    │
    └──→ Redis (where required)
```

Not every application uses every component.

Traefik provides the common access path for most interfaces. PostgreSQL and Redis provide shared application infrastructure where required. Authentik provides centralized authentication where the application and its clients support the required authentication model.

DNS is provided by the network infrastructure rather than by the application layer.

## Docker Networks

The Docker environment uses separate networks to distinguish major classes of service communication.

### `proxy`

The `proxy` network connects services that require Traefik.

It allows Traefik to reach application containers without requiring each application to independently expose its service to the host.

### `data`

The `data` network connects applications that use the shared PostgreSQL and Redis infrastructure.

This provides a common internal path to data services without exposing those services as ordinary user-facing endpoints.

The network structure therefore reflects the role of the service rather than simply placing every container on a single shared network.

## Storage

Applications access shared user data through the NFS storage layer.

The Docker environment assumes that the relevant NFS storage is available; storage availability is therefore an infrastructure prerequisite even though individual containers do not themselves manage the underlying storage system.

For example, media applications consume shared media data rather than maintaining independent copies of the media inside their containers.

Jellyfin similarly reads its media through the shared data path. Its separate LXC deployment is a runtime decision and does not change the underlying storage architecture.

Application configuration and application-local data are maintained within the Docker service directories. These are currently protected primarily through Proxmox VM/container backups rather than through a separate application-level backup mechanism.

## Permissions

Applications that access NFS data may need to run with the appropriate group identity for the underlying storage permissions.

This is particularly relevant for services that need to access shared files while running inside containers.

The system therefore separates:

* application/runtime configuration,
* shared application data,
* and the underlying storage permissions.

The resulting permissions are determined by the storage system and the identities presented by the containers rather than by Docker alone.

## Access and Security

Services are not directly exposed to the public Internet.

Access is restricted to the LAN and VPN.

Where practical, application interfaces are reached through Traefik. Authentication is then handled either by Authentik/forward authentication or by the application's own authentication system when centralized authentication is not compatible with the application.

Core infrastructure services such as Traefik, PostgreSQL, Redis, Authentik, and the monitoring stack are administered through their application interfaces rather than by exposing additional external management interfaces.

The application layer therefore relies on the network layer for its primary access boundary, with authentication and reverse-proxying providing additional controls inside that boundary.

## Availability and Failure Dependencies

The application environment contains deliberate shared dependencies.

If the Docker VM becomes unavailable, the majority of the application layer becomes unavailable.

If Traefik fails, applications may continue running internally but their normal web interfaces will generally become inaccessible.

If Authentik fails, applications that currently rely on forward authentication may be unable to authenticate users. Applications using their own authentication mechanisms are less affected.

If PostgreSQL or Redis fails, applications dependent on those services may become partially or completely unusable.

The monitoring and logging stack is different: its failure should reduce observability rather than directly interrupt application operation.

This creates a practical hierarchy of dependencies:

```text
Network / DNS
      │
      ▼
Docker VM
      │
      ├── Traefik ── Authentik
      │
      ├── PostgreSQL
      │
      ├── Redis
      │
      ├── Monitoring / Logging
      │
      └── Applications
```

The architecture intentionally accepts these shared dependencies in exchange for avoiding duplicated infrastructure across individual applications.

## Backup

Application configuration and container state are included in the Proxmox backup strategy.

The current approach relies on VM/LXC backups rather than implementing independent backup mechanisms for every application.

This means that, from the application's perspective, rebuilding the Docker VM or Jellyfin LXC from a backup is the primary recovery mechanism.

Shared user data remains part of the storage architecture and is handled by the storage system rather than being treated as disposable container data.

## Current Limitations

Several parts of the application architecture remain incomplete or imperfect:

* The monitoring and logging stack is deployed but not yet fully functional.
* Vaultwarden is deployed but not currently in active use.
* Some applications cannot participate cleanly in the centralized authentication model.
* The Docker VM is a major shared dependency and therefore a single failure can affect most applications simultaneously.
* Application data permissions across containers and NFS require careful UID/GID handling.
* Application updates are currently performed manually.
* Application-level backup and recovery procedures have not yet been developed independently of the underlying Proxmox backup system.

These are characteristics of the current system rather than requirements for the intended architecture.

## Design Philosophy

The application layer favors **shared infrastructure and independently deployable applications**.

Applications are kept relatively self-contained in their own Compose projects, while common concerns are centralized into services such as Traefik, Authentik, PostgreSQL, Redis, and the monitoring stack.

This avoids requiring every application to independently solve the same infrastructure problems while retaining the ability to deploy, modify, or remove individual applications without restructuring the entire environment.

Docker Compose is the normal path for service deployment because it provides a declarative description of each application and its dependencies. LXC is reserved for cases where the normal container environment cannot satisfy the application's hardware or runtime requirements.

The result is a small application platform rather than simply a collection of unrelated containers: applications provide the user-facing functionality, while shared services provide the common infrastructure on which those applications operate.
