# High-level management and provisioning of CKAN Cloud clusters

The CKAN Cloud management server provides high-level management and provisioning of CKAN Cloud clusters.

## Create a management server

Set a unique CKAN Cloud namespace name for this cloud management server and create the configuration directory

```
CKAN_CLOUD_NAMESPACE=my-cloud
mkdir -p /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}
```

Generate an SSH key to access the machine

```
ssh-keygen -t rsa -b 4096 -C "admin@ckan-cloud-management" -N "" -f /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-id_rsa
```

Create the server and enable SSH access using the generated key

Following are supported options for creating the server

#### Create a server locally using VirtualBox

Using VirtualBox UI -
* start an Ubuntu server 18.04
* single bridged mode networking interface
* 2 CPU capped at 80%
* 2048mb ram

Log-in to the server and get the IP from ifconfig output:

```
ifconfig
```

The machine must be accessible publically, enable port-forwarding in your router to forward external connections to this IP

Add the ssh public key to root authorized keys in the server:

```
echo "**************" >> /root/.ssh/authorized_keys
```

In the host machine - create the Docker Machine configuration (set the GENERIC_IP_ADDRESS to the IP you got previously)

```
echo "
export GENERIC_IP_ADDRESS=
export MACHINE_DRIVER=generic
export GENERIC_SSH_KEY=/etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-id_rsa
export GENERIC_SSH_USER=root
" > /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-docker-machine.env
```

#### Create a server using Amazon EC2

Create the following AWS resources and note the resource ids

For a secure production deployment, the following resources should be used only for the CKAN cloud management services and separate from the cluster workloads:

* Import the generated SSH key to AWS EC2 key pairs
* VPC
* Security group:
   * allow ports 80 and 443 from anywhere
   * allow SSH from specific IPs
   * allow port 2376 (docker engine) from specific IPs
* Public subnet under the VPC
* Elastic IP

Launch the EC2 instance:

* AMI: Ubuntu Server 18.04 LTS (HVM), SSD Volume Type
* Instance Type: m5d.large (recommended for secure and scalable production deployment)
* Use the previously created VPC / security group / subnet / key-pair / ip

Create the Docker Machine configuration (set the instance's public hostname in GENERIC_IP_ADDRESS)

```
echo "
export GENERIC_IP_ADDRESS=
export MACHINE_DRIVER=generic
export GENERIC_SSH_KEY=/etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-id_rsa
export GENERIC_SSH_USER=ubuntu
" > /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-docker-machine.env
```

Create the Docker Machine

```
source /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-docker-machine.env
docker-machine create ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management
```

If you used the recommended instance type of m5d.large run the following steps as well:

* SSH into the server: `docker-machine ssh ckan-cloud-management`
* Check the name of the unmounted SSD filesystem (something like /dev/nvme1n1): `sudo fdisk -l`
* Create ext4 filesystem: `sudo mkfs.ext4 /dev/nvme1n1`
* Mount: `sudo mkdir /mnt/ssd && sudo mount /dev/nvme1n1 /mnt/ssd`
* Set docker config: `echo '{"data-root":"/mnt/ssd/docker-data"}' | sudo tee /etc/docker/daemon.json`
* Change overlay driver: `sudo sed -i -e 's/aufs/overlay2/g' /etc/systemd/system/docker.service.d/10-machine.conf`
* Reload and restart docker: `sudo systemctl daemon-reload && sudo systemctl restart docker`
* Verify: `sudo docker info | grep /mnt/ssd/docker-data && sudo docker info | grep overlay2`

## Connecting to the management server

You can run the following script multiple times, from multiple hosts to enable access
(assuming you have the server, configuration and keys as described above)

```
source /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-docker-machine.env
docker-machine rm -f ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management
docker-machine create ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management
```

Activate the machine

```
eval $(docker-machine env ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management)
```


Verify Docker Machine installation:

```
docker version && docker run hello-world
```

Verify the activated machine

```
docker-machine active
```

All the following commands should run on the relevant active Docker Machine

## Initialize ckan-cloud-cluster on the management server

Initialize ckan-cloud-cluster, choose a published release from [here](https://github.com/ViderumGlobal/ckan-cloud-cluster/releases)

```
CKAN_CLOUD_CLUSTER_VERSION=0.0.6

curl -L https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-cluster/v${CKAN_CLOUD_CLUSTER_VERSION}/ckan-cloud-cluster.sh \
    | bash -s init $CKAN_CLOUD_CLUSTER_VERSION
```

Alternatively - install latest dev version by cloning the ckan-cloud-cluster repo
and running from the project directory: `./ckan-cloud-cluster.sh init_dev`

## Install Nginx and SSL

Install and configure Nginx and Let's Encrypt (will delete any existing configurations)

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster install_nginx_ssl
```

For AWS - you can get the server's hostname using: `docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster get_aws_public_hostname`

Otherwise - get the public IP of the server.

Set the root domain for the management server and the CKAN instances

```
CKAN_CLOUD_ROOT_DOMAIN="your-domain.com"
```

Set DNS CNAME records or /etc/hosts entries for the following subdomains to this IP (you could prefix/suffix the subdomains to namespace multiple clouds):

* `ckan-cloud-management.${CKAN_CLOUD_ROOT_DOMAIN}`
* `ckan-cloud-jenkins.${CKAN_CLOUD_ROOT_DOMAIN}`

(for maximal security, add a CAA record: `your-domain.com. CAA 128 issue "letsencrypt.org"`)

Register SSL certificates

```
LETSENCRYPT_EMAIL=your@email.com
CERTBOT_DOMAINS="ckan-cloud-management.${CKAN_CLOUD_ROOT_DOMAIN},ckan-cloud-jenkins.${CKAN_CLOUD_ROOT_DOMAIN}"
LETSENCRYPT_DOMAIN=ckan-cloud-management.${CKAN_CLOUD_ROOT_DOMAIN}

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster setup_ssl ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN}
```

## Deploy Rancher

```
RANCHER_SERVER_NAME=ckan-cloud-management.${CKAN_CLOUD_ROOT_DOMAIN}

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_rancher ${RANCHER_SERVER_NAME}
```

Activate via the web-ui at https://ckan-cloud-management.CKAN_CLOUD_ROOT_DOMAIN/

## Deploy Jenkins

Start Jenkins from a published release of [ckan-cloud-docker Jenkins](https://github.com/ViderumGlobal/ckan-cloud-docker/releases)

```
JENKINS_SERVER_NAME=ckan-cloud-jenkins.${CKAN_CLOUD_ROOT_DOMAIN}
JENKINS_IMAGE=viderum/ckan-cloud-docker:jenkins-v0.0.4

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_jenkins ${JENKINS_SERVER_NAME} ${JENKINS_IMAGE}
```

To use a latest dev image, set `JENKINS_IMAGE=viderum/ckan-cloud-docker:jenkins-latest` and re-run the start_jenkins command.

To update from local code, set to latest dev image and build the jenkins image while connected to the docker machine: `cd ckan-cloud-docker; docker-compose build jenkins`,
then restart Jenkins: `docker restart jenkins`

Get the admin password

```
docker-machine ssh $(docker-machine active) sudo cat /var/jenkins_home/secrets/initialAdminPassword
```

Activate via the web-ui at https://ckan-cloud-jenkins.CKAN_CLOUD_ROOT_DOMAIN

On first setup - choose `Install suggested plugins`
