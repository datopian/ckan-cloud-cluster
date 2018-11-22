# CKAN Cloud Cluster Provisioning and Management

Documentation and code for provisioning and running CKAN Cloud clusters.

## Architecture

* **ckan-cloud-management** - a server (or group of servers) which runs centralized management components:
  * **cca-operator** - [Provision, manage and configure Ckan Cloud components](https://github.com/ViderumGlobal/ckan-cloud-docker/blob/master/cca-operator/README.md)
    * Exposes an SSH server to perform admin or automation tasks using limited roles.
    * The cca-operator SSH server listens on port 8022
  * **Nginx + Let's Encrypt**
    * The main HTTPS entrypoint to the management server/s
    * Serves the following services:
    * **Rancher** - [Multi-Cluster Kubernetes Management](https://rancher.com/)
      * Each management server can manage multiple clusters on different cloud providers
      * There is no direct dependency on Rancher, but it's the supported method to provisiong and manage Ckan Cloud clusters.
    * **Jenkins** - [Automation Server](https://jenkins.io/)
      * Used to perform predefined cluster management actions manually or scheduled / as part of CI/CD.
      * There is no direct dependency on Jenkins

* **ckan-cloud-cluster** - a Kubernetes cluster, configured for Ckan Cloud
  * **Ckan Cloud instance**
    * Ckan instances can be created by cca-operator or manually using Rancher / Helm
    * Each Ckan instance is installing in a namespaced named with the instance id.
  * The following cluster-wide resources are required:
    * **Traefik** - [Reverse proxy and load balancer](https://docs.traefik.io/)
      * Main HTTPS entrypoint to the CKAN instances
      * A subdomain is registered for each CKAN instance and configured for SSL with Let's Encrypt
      * cca-operator adds routing for each instance to the Traefik configuration but additional routes can be added manually

## Prerequisites

The management server is provisioned and managed using Docker Machine, you should install it locally -

[Install Docker Machine](https://docs.docker.com/machine/install-machine/)

Following snippet install Docker Machine on Linux (assuming you already have Docker installed):

```
base=https://github.com/docker/machine/releases/download/v0.14.0 &&
curl -L $base/docker-machine-$(uname -s)-$(uname -m) >/tmp/docker-machine &&
sudo install /tmp/docker-machine /usr/local/bin/docker-machine
```

Verify Docker Machine installation:

```
docker-machine version
```

## Provisioning

Follow these guides in this order to provision all the components:

* [Create a management server](docs/MANAGEMENT.md)
* [Create a Kubernetes cluster](docs/CLUSTER.md)
* [Install cca-operator](docs/CCA_OPERATOR.md)
* [Install the provisioning app](docs/PROVISIONING.md)
