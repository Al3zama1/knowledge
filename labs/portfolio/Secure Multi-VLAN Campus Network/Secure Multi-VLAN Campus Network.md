
> Educational home lab built in GNS3 on my own computer. Not a production environment.
> Video walkthrough: [YouTube link](#)

A redundant two-tier campus LAN (collapsed core) for five departments, with VLSM addressing, load-balanced Rapid PVST+, EtherChannel, Layer 2 security, ACL-controlled access, SSH-only management, NTP, syslog and SNMP. I verified it, then found and fixed injected faults.

**Skills shown:** VLSM subnetting, VLANs and 802.1Q trunking, Rapid PVST+, LACP EtherChannel, router-on-a-stick, DHCP, port security, DHCP snooping, DAI, ACLs, SSH hardening, NTP/syslog/SNMP, troubleshooting.

---

## Contents

1. [Objective](#1-objective)
2. [Topology](#2-topology)
3. [Addressing plan (VLSM)](#3-addressing-plan-vlsm)
4. [Tools and environment](#4-tools-and-environment)
5. [Build, step by step](#5-build-step-by-step)
6. [Verification](#6-verification)
7. [Security tests](#7-security-tests)
8. [Troubleshooting: injected faults](#8-troubleshooting-injected-faults)
9. [What I learned](#9-what-i-learned)
10. [Limitations](#10-limitations)
11. [Files in this repo](#11-files-in-this-repo)

---

## 1. Objective

Design and build a redundant, secure campus network for five departments using VLSM addressing, then verify it, document it, and troubleshoot injected faults.

## 2. Topology

![Topology](topology.png)

| Device | Image  | Role                                                                        |
| ------ | ------ | --------------------------------------------------------------------------- |
| R1     | IOSv   | Edge router: inter-VLAN routing (router-on-a-stick), DHCP, ACLs, NTP source |
| DSW1   | IOSvL2 | Distribution switch, STP root for VLANs 10, 20, 99                          |
| DSW2   | IOSvL2 | Distribution switch, STP root for VLANs 30, 40                              |
| ASW1   | IOSvL2 | Access switch: Engineering and Sales                                        |
| ASW2   | IOSvL2 | Access switch: Guests, Servers, Management                                  |

| Link | From | To | Type |
|---|---|---|---|
| 1 | R1 e0/0 | DSW1 e0/0 | Trunk |
| 2, 3 | DSW1 e0/1-2 | DSW2 e0/1-2 | LACP EtherChannel (Po1), trunk |
| 4 | DSW1 e0/3 | ASW1 e0/0 | Trunk |
| 5 | DSW2 e0/3 | ASW1 e0/1 | Trunk |
| 6 | DSW1 e1/0 | ASW2 e0/0 | Trunk |
| 7 | DSW2 e1/0 | ASW2 e0/1 | Trunk |

| Endpoint | Port | VLAN |
|---|---|---|
| PC-ENG | ASW1 e0/2 | 10 |
| PC-SALES | ASW1 e0/3 | 20 |
| ROGUE (Ubuntu + dnsmasq, off until security test) | ASW1 e1/0 | 10 |
| PC-GUEST | ASW2 e0/2 | 30 |
| SRV (Ubuntu: syslog, SNMP polling, NTP tests) | ASW2 e0/3 | 40 |
| ADMIN (Ubuntu, SSH client) | ASW2 e1/0 | 50 |

Unused ports are in VLAN 998 and shut down.

## 3. Addressing plan (VLSM)

Block given: `192.168.10.0/23`. Allocated largest requirement first so every block starts on its own boundary.

| VLAN | Name | Hosts | Network | Usable range | Gateway (R1) |
|---|---|---|---|---|---|
| 10 | ENGINEERING | 100 | 192.168.10.0/25 | .1 to .126 | 192.168.10.1 |
| 30 | GUEST | 50 | 192.168.10.128/26 | .129 to .190 | 192.168.10.129 |
| 20 | SALES | 40 | 192.168.10.192/26 | .193 to .254 | 192.168.10.193 |
| 40 | SERVERS | 20 | 192.168.11.0/27 | .1 to .30 | 192.168.11.1 |
| 99 | MGMT | 12 | 192.168.11.32/28 | .33 to .46 | 192.168.11.33 |
| 50 | IT-ADMIN | 2 | 192.168.11.48/29 | .49 to .54 | 192.168.11.49 |
| 999 | NATIVE | unused | | | |
| 998 | PARKING | unused | | | |

Static addresses: DSW1 .34, DSW2 .35, ASW1 .36, ASW2 .37 (192.168.11.x, VLAN 99); ADMIN 192.168.11.50; SRV 192.168.11.10.

## 4. Tools and environment

- GNS3 with the GNS3 VM, running on a Windows laptop (VMware Workstation or Hyper-V)
- Cisco IOSv and IOSvL2 images
- Ubuntu Docker containers (ROGUE, SRV, ADMIN) with dnsmasq, openssh-client, rsyslog, snmp
- Wireshark (built in to GNS3) for packet captures
- Git for this repository

## 5. Build, step by step

### 5.1 Base configuration
Configure the hostname, domain name, banner and interface descriptions on every device. Each interface description names the connected neighbor device and the port on it. Unused ports are shut down.

| Device | Interface  | Description          |
| ------ | ---------- | -------------------- |
| R1     | e0/0       | DSW1-E0/0            |
| DSW1   | e0/0       | R1-E0/0              |
| DSW1   | e0/1, e0/2 | DSW2-E0/1, DSW2-E0/2 |
| DSW1   | e0/3       | ASW1-E0/0            |
| DSW1   | e1/0       | ASW2-E0/0            |

DSW1 (the other switches use the same configuration with their own hostname and descriptions):
```
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

R1 is configured the same way, with a banner and `no shutdown` on its connected interface:
```
enable
configure terminal
hostname R1
ip domain-name withabran.com
banner motd # Authorized access only #
interface e0/0
 description DSW1-E0/0
 no shutdown
```

``Full configs for every device are in [`configs/`](configs/).``

**Verification**

```
DWS1# show interfaces description
Interface                      Status         Protocol Description
Et0/0                          up             up       R1-E0/0
Et0/1                          up             up       DSW2-E0/1
Et0/2                          up             up       DSW2-E0/2
Et0/3                          up             up       ASW1-E0/0
Et1/0                          up             up       ASW2-E0/0
Et1/1                          admin down     down
Et1/2                          admin down     down
Et1/3                          admin down     down
Et2/0                          admin down     down
Et2/1                          admin down     down
Et2/2                          admin down     down
Et2/3                          admin down     down
Et3/0                          admin down     down
Et3/1                          admin down     down
Et3/2                          admin down     down
Et3/3                          admin down     down



DSW1#show cdp neighbors
Capability Codes: R - Router, T - Trans Bridge, B - Source Route Bridge
                  S - Switch, H - Host, I - IGMP, r - Repeater, P - Phone,
                  D - Remote, C - CVTA, M - Two-port Mac Relay

Device ID        Local Intrfce     Holdtme    Capability  Platform  Port ID
ASW1.withabran.com
                 Eth 0/3           148             R S I  Linux Uni Eth 0/0
ASW2.withabran.com
                 Eth 1/0           155             R S I  Linux Uni Eth 0/0
DSW2.withabran.com
                 Eth 0/2           173             R S I  Linux Uni Eth 0/2
DSW2.withabran.com
                 Eth 0/1           162             R S I  Linux Uni Eth 0/1
R1.withabran.com Eth 0/0           166              R B   Linux Uni Eth 0/0

Total cdp entries displayed : 5

```

`show interfaces description` confirms every description and that unused ports are `admin down`. `show cdp neighbors` confirms the descriptions match the real cabling.

### 5.2 VLANs and trunks
Layer 2 is segmented with VLANs, which improves security and limits the size of broadcast domains. Each VLAN represents a department or network function.

| VLAN | Name        | Purpose                      |
| ---- | ----------- | ---------------------------- |
| 10   | ENGINEERING | Engineering users            |
| 20   | SALES       | Sales users                  |
| 30   | GUEST       | Guest users                  |
| 40   | SERVERS     | SRV                          |
| 50   | IT-ADMIN    | Admin workstation            |
| 99   | MGMT        | Device management            |
| 998  | PARKING     | Unused ports (shut down)     |
| 999  | NATIVE      | Unused native VLAN on trunks |

All four switches have the same VLANs. Ports to other switches or to the router are 802.1Q trunks with the same native VLAN and allowed list. Ports to hosts are access ports, and unused ports are parked in VLAN 998.

| Switch | Trunk ports                  | Access Ports     |
| ------ | ---------------------------- | ---------------- |
| DSW1   | e0/0, e0/1, e0/2, e0/3, e1/0 | none             |
| DSW2   | e0/1, e0/2, e0/3, e1/0       | none             |
| ASW1   | e0/0, e0/1                   | e0/2, e0/3, e1/0 |
| ASW2   | e0/0, e0/1                   | e0/2, e0/3, e1/0 |

ASW1's E1/0 interface is assigned to VLAN 10 to be later used in a DCHP injection attack carried out by a ROGUE client.

**On all switches**

```
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

```
interface range e0/0-3, e1/0
 switchport trunk encapsulation dot1q
 switchport mode trunk
 switchport trunk native vlan 999
 switchport nonegotiate
 switchport trunk allowed vlan 10,20,30,40,50,99
```

**Access and unused ports** (ASW1 shown)

```
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

**Verification**

```
DSW1#show vlan brief

VLAN Name                             Status    Ports
---- -------------------------------- --------- -------------------------------
1    default                          active
10   ENGINEERING                      active
20   SALES                            active
30   GUEST                            active
40   SERVERS                          active
50   IT-ADMIN                         active
99   MGMT                             active
998  PARKING                          active    Et1/1, Et1/2, Et1/3, Et2/0
                                                Et2/1, Et2/2, Et2/3, Et3/0
                                                Et3/1, Et3/2, Et3/3
999  NATIVE                           active
1002 fddi-default                     act/unsup
1003 token-ring-default               act/unsup
1004 fddinet-default                  act/unsup
1005 trnet-default                    act/unsup
```

```
DSW1#show interfaces trunk

Port        Mode             Encapsulation  Status        Native vlan
Et0/0       on               802.1q         trunking      999
Et0/1       on               802.1q         trunking      999
Et0/2       on               802.1q         trunking      999
Et0/3       on               802.1q         trunking      999
Et1/0       on               802.1q         trunking      999

Port        Vlans allowed on trunk
Et0/0       10,20,30,40,50,99
Et0/1       10,20,30,40,50,99
Et0/2       10,20,30,40,50,99
Et0/3       10,20,30,40,50,99
Et1/0       10,20,30,40,50,99

Port        Vlans allowed and active in management domain
Et0/0       10,20,30,40,50,99
Et0/1       10,20,30,40,50,99
Et0/2       10,20,30,40,50,99
Et0/3       10,20,30,40,50,99
Et1/0       10,20,30,40,50,99

Port        Vlans in spanning tree forwarding state and not pruned

Port        Vlans in spanning tree forwarding state and not pruned
Et0/0       10,20,30,40,50,99
Et0/1       10,20,30,40,50,99
Et0/2       10,20,30,40,50,99
Et0/3       10,20,30,40,50,99
Et1/0       10,20,30,40,50,99
```

```
ASW1#show vlan brief

VLAN Name                             Status    Ports
---- -------------------------------- --------- -------------------------------
1    default                          active
10   ENGINEERING                      active    Et0/2, Et1/0
20   SALES                            active    Et0/3
30   GUEST                            active
40   SERVERS                          active
50   IT-ADMIN                         active
99   MGMT                             active
998  PARKING                          active    Et1/1, Et1/2, Et1/3, Et2/0
                                                Et2/1, Et2/2, Et2/3, Et3/0
                                                Et3/1, Et3/2, Et3/3
999  NATIVE                           active
1002 fddi-default                     act/unsup
1003 token-ring-default               act/unsup
1004 fddinet-default                  act/unsup
1005 trnet-default                    act/unsup

```
