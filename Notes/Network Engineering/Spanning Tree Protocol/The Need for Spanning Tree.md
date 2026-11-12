![[article-img.webp]]

Local Area Network (LAN) redundancy is a foundational element of fault‑tolerant network design. By introducing alternate physical paths, redundancy eliminates single points of failure and ensures that traffic can continue flowing even when a link or device goes down. However, redundant Layer 2 paths also create the potential for loops, which can quickly destabilize an entire network. Without a control mechanism such as the Spanning Tree Protocol (STP), redundant links can trigger broadcast storms, MAC address flapping, and widespread connectivity loss.

## Why Redundant LANs CAN Become Unstable
Layer 3 packets include a Time To Live (TTL) field that prevents them from circulating indefinitely. Layer 2 Ethernet frames have no such safeguard. Switches rely on STP to detect redundant paths and block the ones that would otherwise form loops.

When STP is disabled, three types of frames become dangerous:
- Broadcast frames
- Unknown‑unicast frames
- Multicast frames

Because switches flood these frame types out all ports except the one they arrived on, a looped topology causes frames to circulate endlessly. As the volume of looping traffic grows, the network becomes saturated and legitimate traffic can no longer pass.

## Lab Scenario: ARP in a Redundant Topology Without STP
The following example walks through a real lab scenario demonstrating how a simple ARP request can escalate into a broadcast storm when STP is disabled, and how enabling STP immediately restores stability.

![[redundant-scenario-img-1.png]]

PC1 needs to communicate with PC2 but does not yet know its MAC address. Therefore, it sends a broadcast ARP request to obtain it.

- SW1 receives the request, learns PC1’s MAC address on port F0/0, and floods the frame out all other ports.

![[redundant-scenario-img-2.png]]

- SW2 and SW3 receive the broadcast on their F0/1 ports, learn PC1’s MAC address, and flood the frame further.

![[redundant-scenario-img-3.png]]

PC2 receives one of the ARP requests and sends a unicast ARP reply back toward PC1. Meanwhile, SW2 and SW3 also flood the ARP request they received from each other, updating their MAC tables as frames with the same source MAC address arrive on different ports.

![[redundant-scenario-img-4.png]]

The ARP request eventually returns to SW1, which floods it again. The cycle repeats indefinitely. Switches continuously relearn MAC addresses on different ports, and PC2 keeps responding to repeated ARP broadcasts.

At this point, three issues appear:
- A broadcast storm is starting to form from all the frames traveling in circles between switches.
- PC2 will keep receiving multiple ARP requests, even though it already responded.
- All three switches will learn PC1’s MAC address on different ports over time because copies of the same frame will keep looping, causing MAC flapping.

![[redundant-scenario-img-5.png]]

In the previous step, SW2 forwarded PC2’s unicast ARP reply through its F0/2 port, but now it has forwarded it through port F0/1. The looping frames have caused SW2 to learn PC1’s MAC address on a different port, causing changes in the traffic flow.

![[redundant-scenario-img-6.png]]

The network is now in a broadcast storm, consuming bandwidth and switch CPU resources until a link fails or the loop is manually broken.

Because MAC tables are constantly changing:
- SW1 may associate PC1’s MAC with the wrong port.
- ARP replies from PC2 may be forwarded to SW3 or SW2 instead of PC1.
- PC1 may receive replies only sporadically — if at all.
## Observed Behavior in the Lab With STP Disabled

```text
PC1> ping 192.168.1.2  
  
192.168.1.2 icmp_seq=1 timeout  
192.168.1.2 icmp_seq=2 timeout  
192.168.1.2 icmp_seq=3 timeout  
84 bytes from 192.168.1.2 icmp_seq=4 ttl=64 time=1.216 ms  
192.168.1.2 icmp_seq=5 timeout  
  
PC1> ping 192.168.1.2  
  
192.168.1.2 icmp_seq=1 timeout  
192.168.1.2 icmp_seq=2 timeout  
192.168.1.2 icmp_seq=3 timeout  
192.168.1.2 icmp_seq=4 timeout  
192.168.1.2 icmp_seq=5 timeout
```

With STP disabled, there was intermittent success followed by complete failure. Reachability between PC1 and PC2 depends on timing.
## Observed Behavior in the Lab With STP Enabled

```text
PC1> ping 192.168.1.2  
  
84 bytes from 192.168.1.2 icmp_seq=1 ttl=64 time=3.997 ms  
84 bytes from 192.168.1.2 icmp_seq=2 ttl=64 time=2.659 ms  
84 bytes from 192.168.1.2 icmp_seq=3 ttl=64 time=1.957 ms  
84 bytes from 192.168.1.2 icmp_seq=4 ttl=64 time=2.534 ms  
84 bytes from 192.168.1.2 icmp_seq=5 ttl=64 time=3.375 ms
```

With STP active, the redundant path is safely blocked, and communication remains stable between PC1 and PC2.
## Conclusion
LAN redundancy is essential for building resilient, fault‑tolerant networks. However, redundant Layer 2 paths must be controlled to prevent broadcast storms, MAC address flapping, and widespread connectivity issues. As demonstrated in the lab, even a simple ARP request can destabilize a network when STP is disabled. For this reason, STP or one of its modern variants such as RSTP or MSTP is almost always deployed alongside redundant switching topologies.