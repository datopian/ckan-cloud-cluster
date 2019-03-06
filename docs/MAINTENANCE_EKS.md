# Amazon Kubernetes (EKS) Maintenance

## Adding worker nodes

Log-in to Amazon Console and edit the relevant auto scaling group desired instances number.

Verify the nodes were created and connected to the cluster via Rancher.

## Removing / upgrading worker nodes

To remove or upgrade worker nodes to a new Kubernetes version, see [EKS Worker Nodes documentation](https://docs.aws.amazon.com/eks/latest/userguide/worker.html).
