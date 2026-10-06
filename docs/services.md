# Services

The application layer provides the services used by the homelab's users and ties them into shared infrastructure for networking, authentication, data storage, caching, and observability.

Most services run as Docker Compose applications on the Docker VM. Jellyfin is the exception: it runs in its own LXC because it requires more direct access to hardware than the Docker-based application environment currently provides.

The services are intended primarily for personal use by the owner, friends, and family. All services are restricted to the LAN or VPN; none are intended to be directly exposed to the public Internet.

## Service Deployment

Docker Compose is the standard deployment method.

Service deployment definitions are maintained in the public infrastructure repository. The repository itself is the working tree used to deploy the services rather than a separate copy of the deployment configuration.

The repository generally contains:

```text
public-repo/
├── compose/
├── config/
├── docs/
├── scripts/
├── .env.example
└── .gitignore
```

Private configuration and environment-specific values are maintained separately from the public repository.

A single private `.env` file provides environment-specific variables to Docker Compose. It is supplied explicitly when Compose is invoked:

```text
docker compose -f <service>.yml --env-file ../private/.env up -d
```

The `.env` file therefore serves as the central source of deployment variables without automatically exposing all of those variables to every container.

Variables used only for Compose interpolation, such as host paths and hostnames, are not automatically passed into containers. Individual Compose services explicitly declare the environment variables that they require.

For example:

```yaml
environment:
  HOMEPAGE_ALLOWED_HOSTS: ${HOMEPAGE_ALLOWED_HOSTS}
```

This separates **variables used by the deployment system** from **variables intentionally provided to an application**.

The public repository contains an `.env.example` documenting the variables required by the deployment without containing environment-specific values or secrets.

Application configuration is also separated according to sensitivity. Non-sensitive deployment definitions belong in the public repository, while sensitive configuration, credentials, and private application configuration remain outside it.

Application data consumed by a service is kept separate from deployment definitions. Shared user data is provided through the NFS storage layer rather than being embedded into individual containers.

Compose is used because its declarative configuration makes the application environment reproducible and easy to maintain at the individual-service level. It also allows application-specific Traefik configuration to be maintained alongside the application that uses it.

Container management and updates are currently performed manually.

### Image Versioning

Container images are version-pinned rather than relying on floating tags such as `latest`.

Each Compose deployment should specify the intended application version explicitly:

```yaml
image: ghcr.io/example/application:1.2.3
```

Version pinning makes the infrastructure repository an explicit record of which application versions are intended to be deployed. Updates are therefore deliberate changes to the deployment definition rather than implicit changes caused by an upstream tag moving.

Image digests may be used where stronger reproducibility is required, but normal version tags are the standard approach.

Application updates remain a manual process: the desired version is changed in the relevant Compose definition, the service is redeployed, and the resulting application is verified.

LXC is used as an exception when Docker or a conventional VM cannot provide the required access to hardware or other resources. Jellyfin transcoding is a use case for this decision-making.

## Configuration, State, and Runtime Data

The application layer distinguishes between deployment configuration, private configuration, persistent application state, and ephemeral runtime data.

The public repository contains deployment definitions and other non-sensitive infrastructure configuration.

Private configuration and secrets are maintained separately and are supplied to services only where required.

Persistent application state is stored outside the deployment repository. Depending on the application, this may include databases, media libraries, repositories, documents, game data, metadata, or other user-generated content.

Runtime data such as logs, caches, and temporary files are not treated as part of the infrastructure repository.

Where applications support it, logs are preferably emitted to stdout/stderr so that Docker can collect them through its normal logging mechanism. Application logs are therefore not required to be stored alongside Compose definitions or committed to Git.

The repository describes **how a service is deployed**, while persistent storage contains **the state produced by that service**.

## Services

### Application Services

The currently deployed application services are defined in [`/compose`](../compose/).

The Compose directory is the authoritative inventory of Docker-based application deployments. Refer to the individual Compose files for the current services, pinned images, configuration, dependencies, networks, and deployment definitions.

Jellyfin is deployed separately as an LXC rather than through Docker Compose because of its hardware-access requirements.

### Shared Infrastructure Services

Several services exist primarily to support other applications rather than to provide an end-user function themselves.

#### Traefik

Traefik provides reverse-proxying for services with web interfaces.

Applications that expose interfaces generally connect to Traefik rather than being individually exposed. This provides a common entry point for application access and allows routing configuration to remain associated with each application's Compose deployment.

Traefik is therefore a central dependency of the application layer: if it becomes unavailable, applications may continue running but their interfaces will generally no longer be accessible.

#### Authentik

Authentik provides centralized authentication where applications can support it.

The current implementation primarily uses Authentik through Traefik forward authentication rather than requiring every application to implement a compatible identity protocol itself.

Not every application uses Authentik. Some applications have client-specific authentication limitations, particularly where mobile or other non-browser clients are involved. Jellyfin also retains its own authentication mechanism because it does not currently provide a suitable authentication integration for the desired setup.

Applications therefore retain their own authentication mechanisms where centralized authentication is not compatible with their clients or runtime requirements.

#### PostgreSQL

PostgreSQL provides shared relational database infrastructure for applications that require it.

Rather than deploying a separate database server for every application, applications that support the shared PostgreSQL environment use the common database service.

PostgreSQL is therefore part of the shared application infrastructure rather than an application itself.

#### Redis

Redis provides shared caching and related transient data services for applications that require it.

Like PostgreSQL, Redis is centralized so that compatible applications can use a common infrastructure service rather than maintaining independent Redis instances.

#### Monitoring and Logging

The monitoring environment consists of the monitoring and logging services defined in the Compose deployment.

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

Application configuration and persistent application data are maintained outside the public infrastructure repository. The location and ownership of that data depend on the service and its storage requirements.

The deployment repository is therefore not treated as a backup of application state. Git provides version history for infrastructure definitions, while persistent application data is protected through the storage and backup architecture.

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

Sensitive configuration and secrets are intentionally kept outside the public infrastructure repository.

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

Application configuration and container state are included in the Proxmox backup strategy where appropriate.

The current approach relies primarily on VM/LXC backups rather than implementing independent backup mechanisms for every application.

This means that, from the application's perspective, rebuilding the Docker VM or Jellyfin LXC from a backup is an important recovery mechanism.

Persistent application and user data remains part of the storage architecture and is handled by the storage and backup systems rather than being treated as disposable container data.

The infrastructure repository itself is version-controlled independently of application state. Git history provides recovery for deployment definitions, while Proxmox and storage backups provide recovery for the systems and data those definitions operate.

## Current Limitations

Several parts of the application architecture remain incomplete or imperfect:

* The monitoring and logging stack is deployed but not yet fully functional.
* Vaultwarden is deployed but not currently in active use.
* Some applications cannot participate cleanly in the centralized authentication model.
* The Docker VM is a major shared dependency and therefore a single failure can affect most applications simultaneously.
* Application data permissions across containers and NFS require careful UID/GID handling.
* Application updates are currently performed manually.
* Application-level backup and recovery procedures have not yet been developed independently of the underlying Proxmox and storage backup systems.
* Image versions are intentionally pinned, but the update process remains manual.

These are characteristics of the current system rather than requirements for the intended architecture.

## Design Philosophy

The application layer favors **shared infrastructure and independently deployable applications**.

Applications are maintained as independently deployable Compose definitions, while common concerns are centralized into services such as Traefik, Authentik, PostgreSQL, Redis, and the monitoring stack.

This avoids requiring every application to independently solve the same infrastructure problems while retaining the ability to deploy, modify, or remove individual applications without restructuring the entire environment.

The infrastructure repository is treated as the source of truth for service deployment definitions. Public and private configuration are deliberately separated so that the deployment can be version-controlled without publishing sensitive environment-specific information.

A single private environment file provides common deployment variables to Compose, while individual services explicitly declare the variables they require. This prevents the environment file from becoming an implicit source of configuration inside every container.

Persistent application state is treated separately from infrastructure definitions. Git describes and versions the deployment; the storage and backup systems preserve the state generated by that deployment.

Container images are version-pinned so that the repository records the intended application versions. Upgrading an application is therefore an explicit infrastructure change rather than an implicit consequence of a floating image tag.

Docker Compose is the normal path for service deployment because it provides a declarative description of each application and its dependencies. LXC is reserved for cases where the normal container environment cannot satisfy the application's hardware or runtime requirements.

The result is a small application platform rather than simply a collection of unrelated containers: applications provide the user-facing functionality, shared services provide common infrastructure, the repository defines how those services are deployed, and the storage and backup layers preserve the state those services produce.
