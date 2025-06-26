---
title: Beyond CAS: Why the world needs another Kubernetes Cluster Autoscaler
date: 2025-06-14
abstract: Kubernetes' Cluster Autoscaler (CAS) has been the standard for dynamic scaling, but it suffers from limitations that hamper its performance in some scenarios. This talk introduces Karpenter, a modern alternative designed for real-time, workload-specific node provisioning.
conferences:
  - name: DevConf
    location: Brno
    date: 2025-06-14
    slides: /talks/slides/devconf-brno-karpenter.pdf
    recording: https://youtu.be/YDyalb99OZc
---

Kubernetes' Cluster Autoscaler (CAS) has been the standard for dynamic scaling, but it suffers from limitations that hamper its performance in some scenarios.

This talk introduces Karpenter, a modern alternative designed for real-time, workload-specific node provisioning. We will present the development of a custom IBM Cloud Karpenter provider, highlighting its architecture, implementation challenges, and experimental results.

Using the scientific method to benchmark performance, we compare scaling efficiency, cost savings, and resource utilization of CAS and Karpenter across AWS and IBM Cloud in different scenarios.

This session offers practical insights for cloud architects and Kubernetes practitioners looking to optimize autoscaling in cloud-native environments.
