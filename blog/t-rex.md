---
title: Unleashing the T-Rex - How Containers Sometimes Fail to Contain
date: 2024-09-23
author: Josephine Pfeiffer
tags: [containers, security, vulnerabilities, eBPF, jurassic-park]
description: An exploration of container escapes through the lens of Jurassic Park
---

In Jurassic Park, the electric fences were supposed to keep the dinosaurs locked in, but as we all know, things didn't exactly go as planned. Containers are kind of like those dino enclosures-meant to isolate and contain-but under the right conditions, they can break free and cause chaos in the system. In this post, we will explore how containers can escape their supposed isolation, using Jurassic Park terms to help make sense of the low-level system internals.

> This blog post is based on my talk at BSides. If you prefer watching over reading, check out the [full presentation on YouTube](https://www.youtube.com/watch?v=_7R-Ha3cnuE).

## Refresher on Container Basics

Containers package applications and their dependencies into a single bundle that runs on a shared operating system kernel. They're portable, scalable, fast, and mostly isolated. 

Most devs interact with them via Containerfiles, which define how to package everything so it can run anywhere.
In low-level terms, containers run as child processes of the Container Runtime on a host system.

> there is no container - it's just another process running on your machine

Imagine your system as Jurassic Park itself: the hardware is the Island - it's the foundation everything runs on. 
The container runtime (like runc or containerd) acts as the control room, overseeing the whole operation, managing the lifecycle of the containers, and making sure things run smoothly. 
Finally, the containers themselves are the dinosaur enclosures - each one holding a specific app, isolated from the others, but still sharing the same ecosystem (the park).

## Overview of Container Host Separation Mechanisms

![Container Host Separation - An illustration showing how containers are isolated from the host system](/blog/images/container-host-separation.png)

Just like the control room manages which gates to open and close, the container runtime handles when to start, stop, and remove containers. It also provisions isolation mechanisms like namespaces, capabilities, and groups by interfacing with the kernel. 

Ideally, the fences (isolation mechanisms like namespaces, cgroups, and security modules) keep the dinos locked in - but, as we know from Jurassic Park, fences can fail, and when they do, chaos ensues.

## Types of Container Escapes

Container escapes come in a few flavors, all aimed at breaking the supposed isolation between the container and the host.

### Overview of Container Attack Vectors

![Container Attack Vectors - A diagram showing various ways containers can be exploited](/blog/images/container-attack-vectors.png)

One common method is exploiting a misconfigured or overly permissive bind mount, giving the process access to the host's root filesystem. 

Another involves triggering a buffer overflow in a containerized process, allowing an attacker to manipulate shared memory regions. Misconfigurations can also be leveraged to execute commands directly on the host, bypassing container boundaries altogether. 

Finally, attackers can escalate privileges to gain root access on the host, effectively dissolving the container's isolation and taking full control.

## Case Study: eBPF

For the rest of this blog post, we will dig deeper into how a container escape facilitated by eBPF works.

eBPF was originally designed for packet filtering but has since evolved to let user-space code run directly in the kernel without the need for loading LKM drivers. At one point, they even marketed it as doing for the Linux kernel what js does for HTML - though that comparison has quietly disappeared, probably because being linked to js is just a bad look these days.

The cool part about eBPF is that developers don't need to write complex kernel code; it's relatively easy to get started, and depending on the use case it offers significant performance benefits by running directly in the kernel.

### eBPF attack vectors

![eBPF Attack Vectors - Diagram illustrating how eBPF can be exploited](/blog/images/ssdlc.png)

eBPF attack vectors target weaknesses in the eBPF verifier and JIT compiler. Attackers can trick the kernel into loading unsafe bytecode, often by exploiting arithmetic or logic errors during verification. 

In the JIT compiler, bugs in the bytecode compilation process can also be exploited. 

Memory corruption is another route, allowing attackers to overwrite eBPF programs and escalate privileges.

### Deep Dive: eBPF Verifier

The eBPF verifier ensures the safety and security of eBPF programs before they are executed in the kernel. It operates in two main steps:

1. Directed acyclic graph (DAG) check to prevent loops and validate the control flow graph (CFG), ensuring there are no unreachable instructions
2. Simulates execution of every instruction, examining all possible execution paths to observe how each affects the state of registers and the stack

Or in dinosaur terms: Before any new dinosaur is allowed into the park, the verifier makes sure its enclosure is safe. It first checks the basic layout, making sure there are no hidden tunnels or blind spots (no unreachable instructions or loops).

Then, like park security testing every cage and lock, the verifier simulates all possible behaviors of the dinosaur, ensuring that even if it tries to headbutt the fence (execute an instruction), it won't cause an electrical short (invalid memory access) or dig under the barriers (unsafe pointer arithmetic).

### Exploits in the Wild

In recent years, there have been several notable vulnerabilities in the eBPF verifier, which can be exploited for local privilege escalation:
- CVE-2021–3490
- CVE-2023–2163
- CVE-2024–41003

The latest one has only been disclosed in the summer of 2024.

## eBPF Verifier CVE Demo

![eBPF Exploit Demonstration - A screenshot showing the exploit in action](/blog/images/run-exploit.gif)

The exploit we'll be looking at in the demo relies on a flaw in the eBPF verifier's handling of certain arithmetic operations, allowing attackers to manipulate kernel memory and execute arbitrary code.

Think of it as a blind spot in the fence that the control room cameras can't see and raptors can escape if they hit the fence just right.

The exploit works because only the true conditional path will be analyzed by the verifier, we can put whatever instructions we want into the false path and the verifier will accept it. The instructions in the dead branch will be patched with a jump-1 instruction which sets back the counter back one instruction.

This causes an infinite loop - we can cause a DoS by launching many instances of the exploit and locking up all available kernel threads.

The exploit messes with the register to achieve arbitrary write, find the thread's task_struct address, get the cred struct, overwrite cred id to 0 and we have root!

Let's see it in action:

(1) The Containerfile creates a regular user and defines that the container should run under this user

```dockerfile
FROM ubuntu:20.04
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    && apt-get clean

RUN useradd -ms /bin/bash demo
USER demo

WORKDIR /home/demo
COPY --chown=demo:demo . .

RUN make groovy
```

(2) We run the exploit in the container and get full root on the host

(3) We can observe the syscalls made by the exploit on the host system with BPF trace

![BPF trace output showing syscalls from the exploit](/blog/images/bpf-trace.gif)

```bash
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_* /comm == "exploit.bin"/ { printf("%s: %s\n", comm, probe); }'
```

## What Now?

Once you've broken out of a container, the real fun begins. First, you can explore the host network, grab sensitive data, or steal credentials. 

Then comes lateral movement - spawning more privileged containers or spreading across the system like raptors hopping paddocks. 

From there, persistence is key: maybe install a backdoor or ransomware for maximum chaos. 

Phishing attacks also become a possibility if you compromise a mail server or DNS.

It's like having the electric fence codes and sneaking into restricted areas of Jurassic Park - once you're loose, you can wreak havoc.

## How can we prevent this?

Supply chain attacks are one of the main ways exploits and vulnerabilities sneak into systems, often through compromised software dependencies or malicious updates.

![Attack Vectors on the Software Supply Chain - Diagram of supply chain vulnerabilities](/blog/images/ssdlc.png)

When code or components are sourced from third parties, there's a risk that something harmful slips in unnoticed. This is why tools like SBOMs (software bill of materials) and artifact signing/validation are helpful - they give you a clear map of what's inside your containers and ensure that the code hasn't been tampered with. 

It's like checking every crate before it's delivered to Jurassic Park - if you don't, you might just let a raptor in with the supplies.

## Further Reading

![Further reading resources on container security](/blog/images/reading.png)

If you're interested in digging deeper into the technical side of container escapes and eBPF exploits, check out these resources. 

Chompie's blog post on her CVE dive is especially worth reading if you want a detailed breakdown of how she uncovered vulnerabilities in the Linux kernel through eBPF. 

For more on container security and hardening, there's plenty of great material here to keep you from becoming the next Jurassic Park incident.

- [Container Security Basics](https://aquasec.com/cloud-native-academy/container-security/container-security)
- [Hardening Docker Containers](https://redhat.com/en/blog/hardening-docker-containers-images-and-host-security-toolkit)
- [Kernel Pwning with eBPF - a Love Story](https://chomp.ie/Blog+Posts/Kernel+Pwning+with+eBPF+-+a+Love+Story)
- [Deep Dive into CVE-2023-2163](https://bughunters.google.com/blog/6303226026131456/a-deep-dive-into-cve-2023–2163-how-we-found-and-fixed-an-ebpf-linux-kernel-vulnerability)
- [eBPF Bypass Security Monitoring](https://blog.doyensec.com/2022/10/11/ebpf-bypass-security-monitoring.html)