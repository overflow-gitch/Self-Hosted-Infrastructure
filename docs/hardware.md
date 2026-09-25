# Hardware

## 1. Purpose

This document describes the physical hardware comprising the homelab and the hardware constraints that influence its design.

The logical organization of the system is documented in [`architecture.md`](./architecture.md#complete-architecture). Detailed configuration of networking, storage, and application runtimes is documented separately.

This document focuses on:

* Physical hardware and its capabilities
* Hardware resource constraints
* Hardware access and passthrough
* Physical separation of system roles
* Hardware-driven design decisions
* Hardware limitations that motivate future changes

---

## 2. Hardware Inventory

The homelab currently consists of two primary systems, basic network infrastructure, and ISP-provided equipment.

| Component              | Model / Specification | Relevant Characteristics                                         | Role                                     |
| ---------------------- | --------------------- | ---------------------------------------------------------------- | ---------------------------------------- |
| **Node A**             | Lenovo M920q          | Intel i5-8500T, 6C/6T; 16 GB DDR4; 256 GB SSD                    | Primary compute and virtualization       |
| **Node A NIC**         | 4 × Intel I226-V      | 2.5 GbE PCIe NICs                                                | Available for direct hardware assignment |
| **Node A onboard NIC** | Integrated            | 1 GbE                                                            | Host network connectivity                |
| **Node B**             | TC-220                | AMD A10-7800, 4C/4T; 16 GB DDR3; 80 GB SSD; 512 GB HDD; 2 TB HDD | Storage                                  |
| **Node B NIC**         | Integrated            | 1 GbE                                                            | Network connectivity                     |
| **Switch**             | TP-Link TL-SG108      | 8-port unmanaged 1 GbE switch                                    | Physical network connectivity            |
| **Ethernet cabling**   | Cat 5e–Cat 6a         | Mixed cable capabilities                                         | Physical connectivity                    |
| **ISP router**         | ISP-provided          | Details intentionally out of scope                               | Upstream network / modem dependency      |
| **Wireless AP**        | ISP-provided          | Details intentionally out of scope                               | Wireless access dependency               |

The exact physical connections between these components are documented in [`networking.md`](./networking.md).

---

## 3. Compute Hardware

Node A provides the primary compute capacity for the homelab and runs the virtualization layer.

Its hardware establishes the primary resource constraints of the system:

* 6 CPU cores / 6 threads
* 16 GB of system memory
* 256 GB of local SSD storage

These resources limit the number and size of workloads that can be hosted concurrently. The system therefore relies on relatively lightweight virtualization and container workloads rather than high-density virtual machines.

Node A also provides PCIe hardware that can be assigned directly to virtual machines. The four I226-V NICs are currently passed through to the OPNsense virtual machine.

Node B is physically separate from Node A and provides additional compute only insofar as required to operate its storage system. It is not currently part of the primary virtualization cluster.

---

## 4. Storage Hardware

Node B provides physically separate storage capacity from the primary compute system.

Its physical storage consists of:

* An 80 GB SSD for the operating system
* A 512 GB HDD used for backup storage
* A 2 TB HDD providing the primary storage pool

The separation of Node B from Node A means that the primary storage hardware does not reside in the same physical machine as the primary compute hardware.

Detailed dataset organization, storage protocols, snapshots, backup policies, and retention are documented separately in `storage.md`.

---

## 5. Hardware Access and Passthrough

Some workloads require direct access to physical hardware rather than relying entirely on virtualized devices.

The primary example is the four Intel I226-V NICs installed in Node A. These are passed through directly to OPNsense, allowing the virtual machine to interact with the physical interfaces.

This is a hardware-level implementation detail of the current architecture. The resulting network topology and virtual networking configuration are documented separately.

The use of PCIe passthrough also ties those physical interfaces to Node A: they cannot be used independently of the host in their current configuration.

---

## 6. Physical Separation

The current hardware provides two primary physical domains:

* **Node A:** primary compute and virtualization
* **Node B:** primary storage

This separation prevents compute and storage resources from being completely concentrated in one physical machine.

The current network edge does not have the same physical separation. OPNsense is virtualized on Node A, meaning that the availability of the network edge is partially tied to the physical availability of the compute host.

This is a consequence of the current hardware arrangement rather than an inherent requirement of the logical architecture.

---

## 7. Hardware Constraints and Trade-offs

### 7.1 Compute Capacity

Node A's relatively modest CPU, memory, and local storage capacity constrain the amount of infrastructure that can be consolidated onto the host.

The current configuration therefore favors efficient use of virtualization and containerization rather than adding additional compute hardware.

### 7.2 Network Hardware

The current physical network infrastructure is based around an 8-port unmanaged 1 GbE switch.

This provides basic physical connectivity but does not provide the configurable switching capabilities of a managed switch.

Node A has four 2.5 GbE interfaces, but the presence of faster interfaces does not by itself provide end-to-end 2.5 GbE connectivity through the existing 1 GbE switching infrastructure. The base speed of the entire network is considered 1 Gpbs.

The detailed implications for network topology and throughput belong in `networking.md`.

### 7.3 Physical Network Dependencies

The homelab also depends on ISP-provided networking equipment, including the upstream router/modem and wireless access point.

These devices are outside the scope of this hardware inventory beyond acknowledging their existence as external dependencies.

The wireless access point is currently due for replacement.

---

## 8. Hardware-Driven Design Decisions

The current physical configuration reflects several practical decisions:

* **Compute consolidation:** Most compute resources are concentrated on Node A rather than distributed across multiple compute hosts.
* **Separate storage:** Storage is provided by a physically independent Node B rather than relying entirely on Node A's local storage.
* **Hardware passthrough:** Physical NICs are assigned directly to OPNsense where direct hardware access is useful.
* **Minimal network infrastructure:** A relatively simple unmanaged switch is used rather than introducing more capable switching hardware before it is required.

These decisions prioritize making use of existing hardware while accepting its resulting resource and dependency constraints.

---

## 9. Future Hardware Changes

Future hardware changes should address concrete limitations of the current physical configuration rather than reproduce functionality already provided by existing hardware.

Potential changes include:

* Replacing or augmenting the current network infrastructure if greater throughput or switching capabilities become necessary.
* Replacing the wireless access point.
* Increasing compute capacity if Node A's CPU or memory becomes a limiting factor.
* Increasing or reorganizing storage capacity if Node B's available capacity becomes insufficient.
* Introducing dedicated network hardware, separating the network edge from the virtualization host.

The detailed justification for any future network, storage, or runtime redesign belongs in the corresponding subsystem documentation.

---
