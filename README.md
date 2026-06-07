# Self-Hosted-Infrastructure
Systems documentation and automation scripts for a virtualized laboratory environment featuring network isolation, microservices, and multi-layered security.

## Project Overview
This repository documents the architecture and automation of a self-hosted environment built on top of Proxmox VE. The lab is designed to demonstrate proficiency in multi-layered network security, containerized microservices, and infrastructure automation using an enterprise-focused approach.

## Tech Stack
- **Virtualization**: Proxmox VE (Type-1 Hypervisor)
- **Networking/Firewall**: OPNsense (Interface/VLAN management, Firewall, DNS/DHCP (Dnsmasq + Unbound), Wireguard VPN), Nginx Proxy Manager

## Design Decisions

### Hardware
- Edge/General Compute Node 1: Intel 6 cores, 16 GB RAM, OS: Proxmox VE
- Storage Node 1: AMD A10, 16 GB RAM, boot drive, 2 TB hdd, 0.5 tb hdd, boot drive, OS: Proxmox VE 

### Software/Services
- **Proxmox:** Selected for its robust KVM-based virtualization, container support (LXC), and advanced cluster/networking integrations which enables high resource efficiency on constrained hardware.
- **OPNsense:** Deployed OPNsense to serve as the network edge, leveraging hardened BSD security, fine-grained, stateful firewall rules, and integrated VPN support (WireGuard) for secure remote access. Additional integrations for DHCP/DNS (DNSmasq/Unbound DNS) and DDNS (DuckDNS) are also utilized for enhanced security, privacy and performance considerations.
- **DuckDNS** A Free service that allows for Dynamic DNS, as well as being leveraged for certificate authority https compliance.
- **Nginx Proxy Manager:** A service that manages SSL certificates, as well as proxy management for secure communication between subnets.

## Security and Networking
- **Principle of Least Privilege:** This is the main guiding principle. Ideally, any connection, permission and access should be minimal and dictated by task/necessity. Any violation, or deviation from this principle should be a calculated result from constraints.