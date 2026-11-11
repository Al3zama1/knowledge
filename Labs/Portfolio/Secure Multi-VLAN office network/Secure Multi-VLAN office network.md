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
| DSW2   | Distribution switch, STP root for VLANs 30, 40, 40                          |
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
- [[#Step 7 – Assigning IP addresses|Assigned addresses]]: DHCP for client PCs, static addresses for the server, the admin PC and the switch management interfaces.
- [[#Step 8 – Edge protection and port security|Protected the edge with PortFast, BPDU Guard, Root Guard and port security.]]
- [[#Step 9 – DHCP snooping and Dynamic ARP Inspection|Blocked a rogue DHCP server with DHCP snooping and added Dynamic ARP Inspection.]]
- [[#Step 10 – ACLs and SSH-only management|Isolated guests with an inbound ACL and limited the management VLAN to the IT admin subnet with SSH-only access.]]
- [[#Step 11 – NTP, syslog and SNMPv3|Added NTP, syslog and SNMPv3]]

## Implementation
> [!tip] How to read the configs
> Each step names the device it was configured on, and the prompt in every code block shows the device and the mode. When the same configuration applies to several devices, one device is shown in full. The others follow the same pattern: take their interface numbers from the **Network links** and **Client devices** tables, and their VLANs and addresses from the **VLSM addressing plan**.

### Step 1 – Base Configuration
**Configure on**: all devices. **Shown**: DSW1.

Before any switching or routing, every device gets the same baseline: a hostname, a domain name, a legal login banner, a description on every connected interface, and all unused ports shut down.

DSW1:
```text
Switch> enable
Switch# configure terminal
Switch(config)# hostname DSW1
DSW1(config)# ip domain-name withabran.com
DSW1(config)# banner motd # Authorized access only #
DSW1(config)# interface e0/0
DSW1(config-if)# description R1-E0/0
DSW1(config-if)# interface e0/1
DSW1(config-if)# description DSW2-E0/1
DSW1(config-if)# interface e0/2
DSW1(config-if)# description DSW2-E0/2
DSW1(config-if)# interface e0/3
DSW1(config-if)# description ASW1-E0/0
DSW1(config-if)# interface e1/0
DSW1(config-if)# description ASW2-E0/0
DSW1(config-if)# interface range e1/1-3, e2/0-3, e3/0-3
DSW1(config-if-range)# shutdown
DSW1(config-if-range)# end 
DSW1# copy running-config startup-config
```

**Other devices**: DSW2, ASW1, ASW2, and R1 get the same commands with their own hostname. Each interface description names the neighbor at the other end o the link, from the **Network links** table (for example, ASW1 e0/0 is `DSW1-E0/3`). On the access switches, ports facing endpoints are described after the client, from the **Client devices** table (for example, ASW1 e0/2 is `PC-ENG`).

**Why**:
* **Hostnames** show up in the prompt, in logs and in CDP, so you always know which device you're on.
* **Interface descriptions** name the device and port at the other end of each link, which makes `show interfaces status` and troubleshooting much faster.
* **The domain name** is needed later to generate the RSA keys for SSH.
* **The banner**: warns that access is restricted, a standard requirement on managed devices.
* **Shutting down unused ports** means nobody can plug in a spare port and land on the network.
### Step 2 – VLSM addressing plan
**Applies to**: the whole network.

I sized each subnet for its host count, assigning the largest first. Every subnet needs room for its hosts plus the gateway, and the space left at the end of the `/23` is free for future VLANs.

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

**Static addresses**

| **Device**         | VLAN | Address          | Gateway       |
| ------------------ | ---- | ---------------- | ------------- |
| R1 (e0/0.99)       | 99   | 192.168.11.33/28 | -             |
| DSW1 (VLAN 99 SVI) | 99   | 192.168.11.34/28 | 192.168.11.33 |
| DSW2 (VLAN 99 SVI) | 99   | 192.168.11.35/28 | 192.168.11.33 |
| ASW1 (VLAN 99 SVI) | 99   | 192.168.11.36/28 | 192.168.11.33 |
| ASW2 (VLAN 99 SVI) | 99   | 192.168.11.37/28 | 192.168.11.33 |
| SRV                | 40   | 192.168.11.10/27 | 192.168.11.1  |
| ADMIN              | 50   | 192.168.11.50/29 | 192.168.11.49 |
PP-ENG, PC-SALES, and PC-GUEST get their addresses from R1 over DHCP

**Why IT-ADMIN is a /29, not a /30:** the requirement is two admin hosts, and R1's gateway needs an address too, so the VLAN needs three usable addresses plus the two reserved ones (network and broadcast). A /30 has only two usable addresses, so the smallest subnet that fits is a /29, with six usable. The lab uses one of the two admin host addresses today (ADMIN at `.50`), leaving the second ready for another admin workstation.

### Step 3 - VLANs, trunks and native VLAN
**Configured on**: DSW1, DSW2, ASW1, ASW2. **Shown**: DSW1 (VLANs and trunks), ASW1 (access ports)

VLANs - identical on all four switches. VTP is set to transparent so switches never learn or overwrite VLANs from each other.

```text
DSW1> enable
DSW1# configure terminal
DSW1(config)# vtp mode transparent
DSW1(config)# vlan 10
DSW1(config-vlan)# name ENGINEERING
DSW1(config-vlan)# vlan 20
DSW1(config-vlan)# name SALES
DSW1(config-vlan)# vlan 30
DSW1(config-vlan)# name GUEST
DSW1(config-vlan)# vlan 40
DSW1(config-vlan)# name SERVERS
DSW1(config-vlan)# vlan 50
DSW1(config-vlan)# name IT-ADMIN
DSW1(config-vlan)# vlan 99
DSW1(config-vlan)# name MGMT
DSW1(config-vlan)# vlan 998
DSW1(config-vlan)# name PARKING
DSW1(config-vlan)# vlan 999
DSW1(config-vlan)# name NATIVE 
```

**Trunks** - every link in the **Network links** table is a trunk. On DSW1 that's the link to R1 (e0/0),
the two links to DSW2 (e0/1-2) and the links to both access switches (e0/3, e1/0):

```text
DSW1# configure terminal
DSW1(config)# interface range e0/0-3, e1/0
DSW1(config-if-range)# switchport trunk encapsulation dot1q
DSW1(config-if-range)# switchport mode trunk
DSW1(config-if-range)# switchport trunk native vlan 999
DSW1(config-if-range)# switchport nonegotiate
DSW1(config-if-range)# switchport trunk allowed vlan 10,20,30,40,50,99
```

**Other switches**: use the same trunk commands on each switch's trunk ports from the **Network links** table: DSW2 `e0/1-3, e1/0`, ASW1 `e0/0-1`, ASW2 `e0/0-1`

**Access ports** - each endpoint port is locked to one VLAN. ASW1 shown:

```text
ASW1# configure terminal
ASW1(config)# interface range e0/2, e1/0
ASW1(config-if-range)# description ENGINEERING
ASW1(config-if-range)# switchport mode access
ASW1(config-if-range)# switchport access vlan 10
ASW1(config-if-range)# switchport nonegotiate
ASW1(config-if-range)# interface e0/3
ASW1(config-if)# switchport mode access
ASW1(config-if)# switchport access vlan 20
ASW1(config-if)# switchport nonegotiate
```

**ASW2**: the same commands, with the ports and VLANs from the **Client devices** table: e0/2 → VLAN 30, e0/3 → VLAN 40, e1/0 → VLAN 50

**Unused ports** - moved into the parking VLAN and kept shut down. ASW1 shown; the other switches park every port not listed in the tables above:

```text
ASW1# configure terminal
ASW1(config)# interface range e1/1-3, e2/0-3, e3/0-3
ASW1(config-if-range)# switchport mode access
ASW1(config-if-range)# switchport access vlan 998
ASW1(config-if-range)# shutdown
```

**Why**:
* **An unused native VLAN** that isn't in the allowed list means nothing can cross a trunk untagged, which closes off double-tagging VLAN-hopping attacks.
* **`switchport nonegotiate`** disables DTP, so no port can negotiate itself into a trunk. It only works once the port is hard-set to trunk or access mode, so it comes after `switchport mode`.
* **VTP transparent mode** stops a switch with a higher revision number from wiping the VLAN database.
* **Parking unused ports in VLAN 998**, which isn't allowed on any trunk, means a spare port enabled by mistake still can't reach anything.
### Step 4 – EtherChannel (LACP)
**Configured on**: DSW1 and DSW2. **Shown**: DSW1.

Links 2 and 3 between DSW1 and DSW2 form one logical link, so spanning tree doesn't block one of them.

```text
DSW1# configure terminal
DSW1(config)# interface range e0/1-2
DSW1(config-if-range)# channel-group 1 mode active
DSW1(config-if-range)# exit
DSW1(config)# interface port-channel 1
DSW1(config-if)# switchport trunk encapsulation dot1q
DSW1(config-if)# switchport mode trunk
DSW1(config-if)# switchport trunk native vlan 999
DSW1(config-if)# switchport nonegotiate
DSW1(config-if)# switchport trunk allowed vlan 10,20,30,40,50,99
```

**DSW2**: identical, on its e0/1-2.

**Why**: `mode active` uses LACP, the open standard. Both sides negotiate the bundle, so a misconfigured member port gets suspended instead of creating a loop. The port-channel carries the same trunk settings as the physical links.
### Step 5 – Rapid PVST+ and per-VLAN root bridges
**Configured on**: all four switches (Rapid PVST+); DSW1 and DSW2 (root bridges). **Shown**: DSW1 and DSW2.

```text
DSW1# configure terminal
DSW1(config)# spanning-tree mode rapid-pvst
DSW1(config)# spanning-tree vlan 10,20,99 root primary
DSW1(config)# spanning-tree vlan 30,40,50 root secondary
DSW1(config)# end
```

```
DSW2# configure terminal
DSW2(config)# spanning-tree mode rapid-pvst
DSW2(config)# spanning-tree vlan 30,40,50 root primary
DSW2(config)# spanning-tree vlan 10,20,99 root secondary
```

**ASW1 and ASW2**: only `spanning-tree mode rapid-pvsp`. They should never become root.

**Why**: With a single root, each access switch blocks one uplink for every VLAN, so half the bandwidth sits idle. Splitting roots means each uplink forwards for some VLANs and stays as the backup for the others. Each distribution switch is also the secondary root for the other's VLANs, so if one fails the other takes over.
### Step 6 – Inter-VLAN routing and DHCP
**Configuration on**: R1.

R1 routes between VLANs on sub-interfaces of its single link to DSW1 (link 1) and hands out addresses to the client VLANs

```text
R1# configure terminal
R1(config)# interface e0/0
R1(config-if)# no shutdown
R1(config-if)# interface e0/0.10
R1(config-subif)# encapsulation dot1Q 10
R1(config-subif)# ip address 192.168.10.1 255.255.255.128
R1(config-subif)# interface e0/0.20
R1(config-subif)# encapsulation dot1Q 20
R1(config-subif)# ip address 192.168.10.193 255.255.255.192
R1(config-subif)# interface e0/0.30
R1(config-subif)# encapsulation dot1Q 30
R1(config-subif)# ip address 192.168.10.129 255.255.255.192
R1(config-subif)# interface e0/0.40
R1(config-subif)# encapsulation dot1Q 40
R1(config-subif)# ip address 192.168.11.1 255.255.255.224
R1(config-subif)# interface e0/0.50
R1(config-subif)# encapsulation dot1Q 50
R1(config-subif)# ip address 192.168.11.49 255.255.255.248
R1(config-subif)# interface e0/0.99
R1(config-subif)# encapsulation dot1Q 99
R1(config-subif)# ip address 192.168.11.33 255.255.255.240
R1(config-subif)# interface e0/0.999
R1(config-subif)# encapsulation dot1Q 999 native
```

DHCP - ENGINEERING shown:

```text
R1# configure terminal
R1(config)# ip dhcp excluded-address 192.168.10.1 192.168.10.10
R1(config)# ip dhcp pool ENGINEERING
R1(dhcp-config)# network 192.168.10.0 255.255.255.128
R1(dhcp-config)# default-router 192.168.10.1
R1(dhcp-config)# dns-server 192.168.10.1
```

**Other pools**: SALES and GUEST follow the same pattern, using their subnet and gateway from the **VLSM addressing plan**. SRV, ADMIN, and the network devices use static addresses.
### Step 7 – Assigning IP addresses
**Configured on**: all endpoints and switches. **Shown**: PC-GUEST and PC-ENG (DHCP), SRV (static), DSW1 (management SVI)

**DHCP clients** - PC-ENG, PC-SALES and PC-GUEST request an address from R1, which is acting as the DHCP server. 

PC-GUEST (VPCS):
```text
PC-GUEST> ip dhcp
DDORA IP 192.168.10.135/26 GW 192.168.10.129
```
`DDORA` shows the full DHCP exchange completing: Discovery, Offer, Request, Acknowledge.

PC-ENG (Ubuntu)

```text
root@PC-ENG:~# dhclient eth0
root@PC-ENG:~# ip -4 addr show eth0
```

**Other DHCP clients**: PC-SALES uses `ip dhcp` like PC-GUEST and receives an address from the SALES pool.

**Static addresses** - the server and the admin PC need addresses that never change, because ACLs, syslog and SNMP point at them.

SRV (Ubuntu)
```text:
root@SRV:~# ip addr add 192.168.11.10/27 dev eth0
root@SRV:~# ip link set eth0 up
root@SRV:~# ip route add default via 192.168.11.1
```

**Admin**: the same commands with `192.168.11.50/30` and gateway `192.168.11.49`.

**Switch management interfaces** - each switch gets a static address on a VLAN 99 SVI, plus a default gateway so it can reply to the IT-ADMIN subnet:

```text
DSW1# configure terminal
DSW1(config)# interface vlan 99
DSW1(config-if)# ip address 192.168.11.34 255.255.255.240
DSW1(config-if)# no shutdown
DSW1(config-if)# exit
DSW1(config-if)# no ip routing
DSW1(config)# ip default-gateway 192.168.11.33
DSW1(config)# end
```

**Other switches** the same commands with their address from the **Static addresses** table: DSW2 `.35`, ASW1 `.36`, ASW2 `.37`. R1 doesn't need this; its management address is on sub-interface `e0/0.99`.

**Why `ip default-gateway` and not default route**: the switches run as Layer 2 devices with IP routing off, so they use that command to reach other subnets. Consequently, ip routing must be disabled, otherwise the switch will silently ignore the command.

### Step 8 – Edge protection and port security
**Configured on**: ASW1 and ASW2 (edge ports); DSW1 and DSW2 (Root Guard). **Shown**: ASW1 and DSW1.

Every endpoint port gets PortFast for fast startup, BPDU Guard to shut the port if a switch is plugged in, and port security to limit MAC addresses:

```text
ASW1# configure terminal
ASW1(config)# interface range e0/2-3, e1/0
ASW1(config-if-range)# spanning-tree portfast
ASW1(config-if-range)# spanning-tree bpduguard enable
ASW1(config-if-range)# switchport port-security
ASW1(config-if-range)# switchport port-security maximum 2
ASW1(config-if-range)# switchport port-security mac-address sticky
ASW1(config-if-range)# switchport port-security violation restrict
```

**ASW2**: the same commands on its endpoint ports, e0/2-3 and e1/0.

Root Guard on the distribution switches' downlinks to the access switches keeps an access switch from ever becoming root:

```text
DSW1# configure terminal
DSW1(config)# interface range e0/3, e1/0
DSW1(config-if-range)# spanning-tree guard root
```

**DSW2**: the same, on its downlinks e0/3 and e1/0
### Step 9 – DHCP snooping and Dynamic ARP Inspection
**Configured on**: ASW1 and ASW2. **Shown**: ASW1

Only the uplinks toward the distribution switches are trusted, so a DHCP server plugged into an access port gets blocked. I tested this by powering on ROGUE (dnsmasq) on ASW1 e1/0. DAI then checks ARP replies against the snooping binding table.

```
ASW1# configure terminal
ASW1(config)# ip dhcp snooping
ASW1(config)# ip dhcp snooping vlan 10,20,30
ASW1(config)# no ip dhcp snooping information option
ASW1(config)# ip arp inspection vlan 10,20,30
ASW1(config)# interface range e0/0-1
ASW1(config-if-range)# ip dhcp snooping trust
ASW1(config-if-range)# ip arp inspection trust
```

**ASW2**: identical; its uplinks are also e0/0-1

Snooping and DAI cover the DHCP client VLANs only (20,20,30). SRV and ADMIN have static addresses with no snooping bindings, so DAI on VLANs 40 or 50 would drop their ARP traffic unless an ARP ACL was added.

**Why** `no ip dhcp snooping information option`: By default the switch inserts option 82 into DHCP requests, and the IOS DHCP server on R1 drops them. Turning it off lets clients get addresses while snooping stays on.
### Step 10 – ACLs and SSH-only management
**Configured on**: R1 (ACLs); all devices (SSH and management access). **Shown**: R1 and DSW1.

**Guest isolation (R1)**: an inbound ACL on the guest sub-interface blocks internal networks but still permits the DHCP exchange.

```text
R1# configure terminal
R1(config)# ip access-list extended GUEST-IN
R1(config-ext-nacl)# permit udp any eq bootpc any eq bootps
R1(config-ext-nacl)# deny ip 192.168.10.128 0.0.0.63 192.168.10.0 0.0.1.255
R1(config-ext-nacl)# permit ip 192.168.10.128 0.0.0.63 any
R1(config-ext-nacl)# exit
R1(config)# interface e0/0.30
R1(config-subif)# ip access-group GUEST-IN in
```

**Management lockdown (R1)**: only the IT-ADMIN subnet can reach the management VLAN.

```
R1# configure terminal
R1(config)# ip access-list extended MGMT-OUT
R1(config-ext-nacl)# permit ip 192.168.11.48 0.0.0.7 192.168.11.32 0.0.0.15
R1(config-ext-nacl)# deny ip any any log
R1(config-ext-nacl)# exit
R1(config)# interface e0/0.99
R1(config-subif)# ip access-group MGMT-OUT out
```

**SSH and VTY access DSW1**

```
DSW1# configure terminal
DSW1(config)# crypto key generate rsa modulus 2048
DSW1(config)# ip ssh version 2
DSW1(config)# username admin privilege 15 secret strong-password
DSW1(config)# ip access-list standard SSH-FROM-IT
DSW1(config-std-nacl)# permit 192.168.11.48 0.0.0.7
DSW1(config-std-nacl)# exit
DSW1(config)# line vty 0 4
DSW1(config-line)# login local
DSW1(config-line)# transport input ssh
DSW1(config-line)# access-class SSH-FROM-IT in
```

**Other devices:** DSW2, ASW1, ASW2 and R1 use the same commands. They're reachable at the management addresses set in [[#Step 7 – Assigning IP addresses|Step 7]].

**Why the admin PC has its own VLAN:** A router ACL only filters traffic that passes _through_ the router. If ADMIN shared a VLAN with other users, those users could reach it directly at Layer 2, so the ACL would protect nothing.
## Verification

|Check|Device|Command|What proves it works|
|---|---|---|---|
|VLANs exist and ports are assigned|All switches|`show vlan brief`|All VLANs active; endpoint ports in the right VLAN|
|Trunks are up with the right native VLAN|All switches|`show interfaces trunk`|Native VLAN 999, allowed VLANs `10,20,30,40,50,99`|
|EtherChannel is bundled|DSW1, DSW2|`show etherchannel summary`|Po1 shows `(SU)`, both members `(P)`|
|Root bridges are split|DSW1, DSW2|`show spanning-tree root`|DSW1 root for 10/20/99, DSW2 root for 30/40/50|
|Clients get addresses|R1|`show ip dhcp binding`|Bindings for PC-ENG, PC-SALES and PC-GUEST|
|Management SVIs are up|All switches|`show ip interface brief`|`Vlan99` up/up with the right address|
|Snooping is building its table|ASW1, ASW2|`show ip dhcp snooping binding`|One entry per DHCP client|
|Rogue DHCP is blocked|ROGUE, PC-ENG|Power on ROGUE, renew PC-ENG's lease|PC-ENG still gets its address from R1|
|Guests can't reach internal networks|PC-GUEST|`ping` to PC-ENG and SRV|Pings fail|
|SSH only from IT admin|ADMIN, PC-SALES|`ssh admin@192.168.11.34`|ADMIN connects; PC-SALES is refused|

## Result & Key Learning Outcomes
- Showed that splitting root bridges per VLAN uses both uplinks instead of leaving one idle.
- Learned that an inbound ACL can break DHCP unless the DHCP exchange is permitted.
- Saw how DHCP snooping and BPDU Guard stop rogue devices at the access port.
- Learned that a router ACL cannot protect hosts in the same VLAN, so the admin PC belongs in its own VLAN.
- Practiced a repeatable troubleshooting method across seven injected faults.
## Skills Demonstrated
- VLSM subnetting
- VLANs and trunking
- Spanning tree 
- EtherChannel
- Switch Security
- DHCP
- Troubleshooting

## Files
- [All files for this lab](https://github.com/Al3zama1/knowledge/tree/main/Labs/Portfolio/Secure%20Multi-VLAN%20office%20network)