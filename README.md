# README

## Overview

This repository provides an automated setup for creating a local Kubernetes cluster using Kind and configuring MetalLB as a load balancer. It includes scripts to set up the cluster, configure MetalLB, and test load balancer functionality with a sample Nginx deployment.

## Features

- **Kind Cluster Creation**: Automates the creation of a local Kubernetes cluster using Kind.
- **MetalLB Configuration**: Dynamically calculates the IP range for MetalLB based on the Kind network and deploys it for load balancer functionality.
- **Load Balancer Testing**: Verifies the setup by deploying a sample Nginx application and exposing it through a LoadBalancer service.

## Usage

1. **Set Up the Cluster**: Run the task to create the Kind cluster and configure MetalLB.
2. **Test Load Balancer**: Deploy the sample Nginx application to validate MetalLB functionality.
3. **View the Nginx Page**: Navigate to the LoadBalancer IP in your browser to see the default Nginx page.
4. **Clean Up**: Use the cleanup task to remove the Kind cluster when finished.

## Task Descriptions

- **`setup-cluster`**: Creates a Kind cluster and configures MetalLB using dynamically calculated IP ranges.
- **`test-loadbalancer`**: Deploys an Nginx application and a LoadBalancer service. After the service is ready, navigate to the LoadBalancer IP in your browser to view the default Nginx page.
- **`all`**: Runs both the setup and testing tasks sequentially.
- **`clean`**: Deletes the Kind cluster and its associated resources.

## General Workflow

1. Run the `setup-cluster` task to create the Kind cluster with MetalLB configuration.
2. Run the `test-loadbalancer` task to deploy Nginx and expose it with a LoadBalancer service.
3. Once the service is ready, open your browser and navigate to the LoadBalancer IP to verify the Nginx deployment.
4. Use the `clean` task to remove the Kind cluster and free up resources.

This repository is ideal for local development and testing MetalLB with Kubernetes clusters.