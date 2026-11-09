---
tags:
  - lab
  - switching
  - vlans
  - stp
  - etherchannel
  - security
  - dhcp
type: lab
category: portfolio
date: 2026-11-08
video:
---

> [!info] Lab environment
> This lab ran in GNS3 on my own computer for educational purposes. Nothing here took place in a production or employer environment.

## Challenge / Objective
Design and build a redundant, secure campus network for five departments using VLSM addressing, then verify it, document it and troubleshoot injected faults.

## Video walkthrough
![](https://www.youtube.com/watch?v=VIDEO_ID)

## Lab Architecture
![[topology.png]]

- Two distribution switches (**DSW1**, **DSW2**) and two access point switches (**ASW1**, **ASW2**) with redundant uplinks
- A LACP EtherChannel between the distribution switches
- Router-on-a-stick inter-VLAN routing on R1, with the DHCP server on the edge router
- Six VLANs subnetted from `192.168.10.0/23` using VLSM, including a separate IT admin VLAN.
- A management VLAN that only the IT admin subnet can reach, through SSH

**Network devices**

| Device | Role                                                                        |
| ------ | --------------------------------------------------------------------------- |
| R1     | Edge router: inter-VLAN routing (router-on-a-stick), DHCP, ACLs, NTP source |
| DSW1   | Distribution switch, STP root for VLANs 10, 20, 99                          |
| DSW2   | Distribution switch, STP root for VLANs 30, 40                              |
| ASW1   | Access switch: Engineering and Sales                                        |
| ASW2   | Access switch: Guests, Servers, Management                                  |

**Network links**

| Link | From        | To          | Type                           |
| ---- | ----------- | ----------- | ------------------------------ |
| 1    | R1 e0/0     | DSW1 e0/0   | Trunk                          |
| 2, 3 | DSW1 e0/1-2 | DSW2 e0/1-2 | LACP EtherChannel (Po1), trunk |
| 4    | DSW1 e0/3   | ASW1 e0/0   | Trunk                          |
| 5    | DSW2 e0/3   | ASW1 e0/1   | Trunk                          |
| 6    | DSW1 e1/0   | ASW2 e0/0   | Trunk                          |
| 7    | DSW2 e1/0   | ASW2 e0/1   | Trunk                          |

**Client devices**

| Endpoint                                          | Port      | VLAN |
| ------------------------------------------------- | --------- | ---- |
| PC-ENG (Ubuntu)                                   | ASW1 e0/2 | 10   |
| PC-SALES (VPC)                                    | ASW1 e0/3 | 20   |
| ROGUE (Ubuntu + dnsmasq, off until security test) | ASW1 e1/0 | 10   |
| PC-GUEST (VPC)                                    | ASW2 e0/2 | 30   |
| SRV (Ubuntu: syslog, SNMP polling, NTP tests)     | ASW2 e0/3 | 40   |
| ADMIN (Ubuntu, SSH client)                        | ASW2 e1/0 | 50   |

## Tools & Technologies
GNS3 · Cisco OS · VLANs · Rapid PVST+ · EtherChannel · DHCP Snooping · DAI · Port Security · SSH

## What I Implemented
- [[#Step 1 – Base Configuration|Applied a base configuration]] to every device: hostname, domain name, login banner, interface descriptions and unused ports shut down.
- [[#Step 2 – VLSM addressing plan|Subnetted the address block with VLSM]] and documented every VLAN, gateway and range.
- [[#Step 3 - VLANs, trunks and native VLAN|Configured access ports, 802.1Q trunks, a custom native VLAN and disabled DTP.]]
- [[#Step 4 – EtherChannel (LACP)|Bundled the distribution uplinks into an LACP EtherChannel.]]
- [[#Step 5 – Rapid PVST+ and per-VLAN root bridges|Ran Rapid PVST+ with a different root bridge per VLAN]] so both uplinks carry traffic.
- [[#Step 6 – Inter-VLAN routing and DHCP|Set up router-on-a-stick inter-VLAN routing and DHCP on R1.]]
- [[#Step 7 – Edge protection and port security|Protected the edge with PortFast, BPDU Guard, Root Guard and port security.]]
- [[#Step 8 – DHCP snooping and Dynamic ARP Inspection|Blocked a rogue DHCP server with DHCP snooping and added Dynamic ARP Inspection.]]
- [[#Step 9 – ACLs and SSH-only management|Isolated guests with an inbound ACL and limited the management VLAN to the IT admin subnet with SSH-only access.]]
- [[#Step 10 – NTP, syslog and SNMPv3|Added NTP, syslog and SNMPv3]], then [[#Troubleshooting – seven injected faults|found and fixed seven injected faults]].

## Implementation

### Step 1 – Base Configuration
Before any switching or routing, every device gets the same baseline: a hostname, a domain name, a legal login banner, a description on every connected interface, and all unused ports shut down. Here is DSW1:

| Device | Interface  | Description          |
| ------ | ---------- | -------------------- |
| R1     | e0/0       | DSW1-E0/0            |
| DSW1   | e0/0       | R1-E0/0              |
| DSW1   | e0/1, e0/2 | DSW2-E0/1, DSW2-E0/2 |
| DSW1   | e0/3       | ASW1-E0/0            |
| DSW1   | e1/0       | ASW2-E0/0            |
DSW1:
```text
enable
configure terminal
hostname DSW1
ip domain-name withabran.com
banner motd # Authorized access only #
interface e0/0
 description R1-E0/0
interface e0/1
 description DSW2-E0/1
interface e0/2
 description DSW2-E0/2
interface e0/3
 description ASW1-E0/0
interface e1/0
 description ASW2-E0/0
interface range e1/1-3, e2/0-3, e3/0-3
 shutdown
```

DSW2, ASW1, ASW2, and R1 follow the same pattern with their own hostnames and neighbors.

**Why**:
* **Hostnames** show up in the prompt, in logs and in CDP, so you always know which device you're on.
* **Interface descriptions** name the device and port at the other end of each link, which makes `show interfaces status` and troubleshooting much faster.
* **The domain name** is needed later to generate the RSA keys for SSH.
* **The banner**: warns that access is restricted, a standard requirement on managed devices.
* **Shutting down unused ports** means nobody can plug in a spare port and land on the network.

### Step 2 – VLSM addressing plan
I sized each subnet for its host count, assigning the largest first so the `/23` block is used with no gaps.

| VLAN | Name        | Hosts | Subnet                        | Usable range          | Gateway (R1)   |
| ---- | ----------- | ----- | ----------------------------- | --------------------- | -------------- |
| 10   | ENGINEERING | 100   | 192.168.10.0/25               | 192.168.10.1 – .126   | 192.168.10.1   |
| 30   | GUEST       | 50    | 192.168.10.128/26             | 192.168.10.129 - .190 | 192.168.10.129 |
| 20   | SALES       | 40    | 192.168.10.192/26             | 192.168.10.193 .254   | 192.168.10.193 |
| 40   | SERVERS     | 20    | 192.168.11.0/27               | 192.168.11.1 - .30    | 192.168.11.1   |
| 99   | MGMT        | 12    | 192.168.11.32/28              | 192.168.11.33 - .46   | 192.168.11.33  |
| 50   | IT-ADMIN    | 2     | 192.168.11.48/29              | 192.168.11.49 - .54   | 192.168.11.49  |
| 999  | NATIVE      | -     | unused (trunk native VLAN)    | -                     | -              |
| 998  | PARKING     | -     | unused (holds shutdown ports) | -                     | -              |

Free for growth: `192.168.11.56 - 192.168.11.255`
Static management addresses: R1 `.33`, DSW1 `.34`, DSW1 `.35`, ASW1 `.36`, ASW2 `.37`

**Why IT-ADMIN is a /29, not a /30**: the lab has one admin PC, so with the gateway the VLAN needs two addresses, and a /30 would fit exactly. I used a /29 instead to leave room for growth: it gives six usable addresses, enough for a second admin workstation without re-addressing the VLAN or rewriting the management ACLs.

### Step 3 - VLANs, trunks and native VLAN
I created the same VLANs on all four switches, set an unused native VLAN, and disabled DTP so no port can negotiate itself into a trunk.

```text
vtp mode transparent

vlan 10
 name ENGINEERING
vlan 20
 name SALES
vlan 30
 name GUEST
vlan 40
 name SERVERS
vlan 50
 name IT-ADMIN
vlan 99
 name MGMT
vlan 998
 name PARKING
vlan 999
 name NATIVE
 
```

**Trunk ports** (DSW1 shown, use the trunk ports from the table on each switch)

```text
interface range e0/0-3, e1/0
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport nonegotiate
 switchport trunk allowed vlan 10,20,30,40,50,99
```

**Access and unused ports** (ASW1 shown)

```text
interface range e0/2, e1/0
 switchport mode access
 switchport access vlan 10
interface e0/3
 switchport mode access
 switchport access vlan 20
interface range e1/1-3, e2/0-3, e3/0-3
 switchport mode access
 switchport access vlan 998
```

On the distribution switches , the unused ports are parked the same way (e1/1-3, e2/0-3, e3/0-3).

## Verification
Show the key `show` commands and explain what in the output proves it works.

```text
! paste show command output here
```

## Troubleshooting

### Fault 1 – Short name
**Symptom:** What you noticed.
**Cause:** What was actually wrong.
**Fix:** What you changed, and how you confirmed it worked.

```text
! relevant output or config
```

## Result & Key Learning Outcomes
- 
- 

## Skills Demonstrated
- 
- 

## Files
- [All files for this lab](https://github.com/al3zama1/knowledge/tree/main/Labs/Portfolio/LAB-FOLDER/files)



> Educational home lab built in GNS3 on my own computer. Not a production environment.
> Video walkthrough: [YouTube link](#)

A redundant two-tier campus LAN (collapsed core) for five departments, with VLSM addressing, load-balanced Rapid PVST+, EtherChannel, Layer 2 security, ACL-controlled access, SSH-only management, NTP, syslog and SNMP. I verified it, then found and fixed injected faults.

**Skills shown:** VLSM subnetting, VLANs and 802.1Q trunking, Rapid PVST+, LACP EtherChannel, router-on-a-stick, DHCP, port security, DHCP snooping, DAI, ACLs, SSH hardening, NTP/syslog/SNMP, troubleshooting.

---
