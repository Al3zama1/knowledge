Spanning Tree Protocol (STP) prevents the formation of Layer 2 loops in redundant Local Area Network (LAN) topologies by placing redundant ports in a blocking state. These ports act as backups that can enter a forwarding state if an active port fails. By selecting which ports are forwarding and which ports are blocked, STP creates a single active path between any two devices.

STP performs the following network convergence steps in this exact order to guarantee a LAN without loops:
- A single switch is elected as the Root Bridge.
- All non-root switches elect one of their ports as their Root port.
- All remaining redundant links (collision domains) elect a Designated and Alternate port.

### Bridge Protocol Data Unit

Bridge Protocol Data Units (BPDUs) are STP control messages exchanged between switches. They allow switches to build and maintain a loop‑free topology and to signal when topology changes occur. There are two types of BPDUs: Configuration BPDUs and Topology Change Notification (TCN) BPDUs.

- Configuration BPDUs define the spanning-tree topology by participating in the Root Bridge election process, advertising path costs, and assigning port roles.
- Topology Change Notification BPDUs are sent by switches when a topology change is detected.

> When BPDU appears by itself, assume it refers to configuration BPDU.

## STP Bridge ID

Bridge ID (BID) is a field within BPDUs used in the Root Bridge election process. It consists of a switch’s priority value and MAC address.

![[stp-bridge-id.webp]]

- The Bridge Priority is compared first, and in case of a tie, the switch with the lowest MAC address value becomes the Root Bridge.
- All switches are given an initial Bridge Priority value of 32768, therefore by default the MAC address is used as the tiebreaker.
## Per-VLAN Bridge ID
Network equipment vendors like Cisco built their own improved versions on top of the industry standard. These improved versions allow switches to run a separate STP instance per-VLAN instead of a single instance per-switch.

![[stp-pv-bridge-id.webp]]

The original Bridge Priority field was split into two sub‑fields to incorporate the Extended System ID (VLAN ID), allowing switches to support multiple STP instances simultaneously.

- The Extended System ID is determined by the VLAN in which the STP instance operates. Because switches run their default STP instance in VLAN 1, the default Extended System ID is 1.
- The Bridge Priority remains unchanged with a default value of 32768.
- The Extended System ID is added to a switch’s priority value to calculate the final Bridge Priority. Therefore, the new default Bridge Priority is 32769.

The BID can be changed to influence the Root Bridge election process.

![[stp-pv-bridge-id-detail.webp]]

- The Extended System ID is set and cannot be changed because it is determined by the VLAN where the STP instance is running.
- It is only possible to change a switch’s priority value in units of 4096.
## Root Bridge
A single switch is elected as the Root Bridge, which functions as the central reference point in the LAN. It influences the logical data flow and sets the STP settings that must be used by other switches. All other switches are considered non-root switches. Non-root switches make path-cost calculations and assign each of their ports a role with respect to the Root Bridge.

- When a switch is powered on, it assumes it is the Root Bridge. It will only give up its position if it receives a superior BPDU with a lower BID.
- Once the topology has converged and all switches agree on the Root Bridge, only it will send BPDUs every 2 seconds out its Designated ports. Other switches in the network will forward these BPDUs, but will not generate their own.
- The Root Bridge has a Designated port in each collision domain it is connected to.

![[stp-root-bridge-election.webp]]

All switches have the default Bridge Priority, but SW1 has the lowest MAC address value; therefore, it is elected as the Root Bridge.
## Port Cost
STP assigns each switch port a cost relative to its operational speed. Higher‑speed ports receive lower costs, making them more preferred paths toward the Root Bridge.

![[stp-port-cost.webp]]

By default switches use the short path cost metric to assign costs to their ports. However, the long path cost metric should be used when there is ports with speeds greater than 10 Gbps.
## Root Port
The Root Port provides the lowest‑cost upstream path for a non‑root switch to reach the Root Bridge. Because it represents the switch’s optimal upstream port, it is used to send TCN BPDUs upstream when a topology change is detected. Upstream switches must not block a switch’s main path to the Root Bridge, therefore ports across from a Root port are always Designated.

The Root port is elected using the following tiebreakers in this exact order:
- Lowest Root cost
- Lowest neighbor Bridge ID
- Lowest Neighbor Port ID (Port Priority + Internal Port Number)
### Root Port Election: Root Cost
Non-root switches will elect their port with the lowest Root cost as their Root port. Root cost is the total cost of the outgoing ports along the path to the Root Bridge.

![[stp-root-port-election-root-cost.webp]]

All switch ports in the diagram above are Ethernet ports, therefore they all have an outgoing cost of 100. SW2 elects its e0/1 port as its Root port with a total Root cost of 100. Its e0/2 port has a total Root cost of 300 (SW2 e0/2 + SW4 e0/1 + SW3 e0/0). The same principle applies with SW3, which elects its e0/0 port as its Root port.
### Root Port Election: Lowest Neighbor Bridge ID
When there is a tie for the lowest Root cost, the port connected to the neighbor switch with the lowest Bridge ID is elected as the Root port.

![[stp-root-port-election-lowest-neighbor-bridge-id.webp]]

SW4 elects port e0/0 as its Root port because both of its active ports have the same Root cost and SW2 has a lower Bridge ID than SW3.
### Root Port Election: Port ID
When there is a tie for the lowest neighbor Bridge ID, the port connected to the neighbor port with the lowest Port ID (port priority + internal port number) is elected as the Root port. The port priority is compared first, and in case of a tie, the internal port number breaks the tie.

- Each switch port is given a STP port ID, which consists of a switch’s port priority and internal port number.
- The default port priority is 128, but can be changed in increments of 16 to influence the Root port election process.
- A switch’s internal port number generally correlates with its physical port label. Lower‑numbered interfaces typically receive lower internal port numbers.

![[stp-root-port-election-port-id.webp]]

SW4 elects e0/2 as its Root port because SW2’s e0/2 has a lower STP port ID than SW2’s e0/3. Both ports on SW2 use the same port priority (128), but lower‑numbered physical ports typically correspond to lower internal port numbers, giving e0/2 the lower Port ID.

![[stp-root-port-election-port-id-verification.webp]]

We can verify that SW2’s e0/2 has a lower internal port number and it is connected to SW4’s e0/2 port. Therefore, SW4 elects e0/2 as it Root port.
### Designated Port
STP prevents the formation of loops by stopping the flow of regular data traffic through redundant links (collision domains) between switches. To achieve this, one side of every redundant link becomes a Designated port and the other an Alternate port.

The Designated port in a redundant link is elected with the following tiebreakers in this exact order:
- The port on the switch with the lower Root cost.
- The port on the switch with the lower Bridge ID
### Designated Port Election: Root Cost
The port on the switch with the lowest Root cost is elected as the Designated port.

![[stp-designated-port-election-root-cost.webp]]

For the redundant link between SW3 and SW4, SW3’s e0/1 is elected as the Designated port because SW3 has a lower Root cost than SW4. Similarly, SW2’s e0/3 is elected as the Designated port because SW2 has a lower Root cost than SW4.
### Designated Port Tiebreaker: Bridge ID
When both sides of a redundant link have the same Root cost, the port on the switch with the lower Bridge ID is elected as the Designated port.

![[stp-designated-port-election-bridge-id.webp]]

SW2 elects its e0/1 port as the Designated port because both switches have the same Root cost and it has a lower Bridge ID.
## STP Port Roles/States
Port roles and states shape the logical data flow by determining what type of data each port is able to receive and forward. A port’s role identifies its logical responsibility in the STP topology, whereas its state reflects its present operational capabilities, such as forwarding user data, learning MAC addresses, or remaining blocked.

![[stp-states.webp]]

- **Alternate** ports are redundant ports that remain in a **blocking** state. They only receive STP messages and react to changes in the STP topology to become active if needed. Alternate ports prevent Layer 2 loops by not forwarding regular data traffic
- **Root** and **Designated** ports are active ports that operate in a **forwarding** state. They send and receive regular data traffic as well as STP messages.
- **Listening** and **Learning** are transitory states that a newly activated or Blocked port pass through when transitioning to the Forwarding state.
## STP Timers
Spanning Tree is a timer‑driven protocol that uses coordinated timers to control BPDU transmission, validate the stability of the topology, manage port‑state transitions, and handle topology‑change events. The Root Bridge dictates the timer values used throughout the network, and all non‑root switches must adopt these settings even if their local configurations differ.

![[stp-timers.webp]]

- The **Hello** timer indicates the interval at which switches will send BPDUs. After a Root Bridge is elected, only it will continue to send BPDUs at that interval.
- Switch ports must wait a **Forward Delay** timer at the Listening and Learning states when transitioning to the forwarding state. A total of 30 seconds is the time that it takes for a recently activated or blocked port to transition to the forwarding state.
- The **Max Age** is the period a switch will wait after seizing to receive BPDUs, before it starts to reconsider its STP choices.
## Spanning Tree Shortcomings
Spanning Tree can be considered slow for today’s standards due to the time it takes a port to transition to the forwarding state. A port will first wait 20 seconds after seizing to receive BPDUs before it transitions to the Listening State. After remaining 15 seconds there, it will transition to the Learning state and remain there for another 15 seconds. In total a port can take a total of 50 seconds to reach the forwarding state. Because of this, a newer much faster version known as Rapid Spanning Tree that does not rely on timers is now the preferred option.