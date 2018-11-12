# CKAN Cloud Cluster Provisioning and Management

Documentation and code for provisioning and running a CKAN Cloud cluster.

## Setup the CKAN Cloud management server

The CKAN Cloud management server is used to setup the Kubernetes cluster and handle different aspects of managing the CKAN Cloud service.

* [Install Docker Machine](https://docs.docker.com/machine/install-machine/)
  * Following works on Linux:

```
base=https://github.com/docker/machine/releases/download/v0.14.0 &&
curl -L $base/docker-machine-$(uname -s)-$(uname -m) >/tmp/docker-machine &&
sudo install /tmp/docker-machine /usr/local/bin/docker-machine
```

Verify:

```
docker-machine version
```

Create (or use existing) AWS resources and note the resource ids

For a secure production deployment, the following resources should be used only for the CKAN cloud management services and separate from the cluster workloads:

* VPC
* Security group:
   * allow ports 80 and 443 from anywhere
   * allow SSH from specific IPs
   * allow port 2376 (docker engine) from specific IPs
* Public subnet under the VPC
* SSH key to access the machine:
  * `ssh-keygen -t rsa -b 4096 -C "admin@ckan-cloud-management" -f /etc/ckan-cloud/.cloud-management-id_rsa`
  * Import the SSH key to AWS EC2 key pairs
* Elastic IP

Launch the EC2 instance:

* AMI: Ubuntu Server 18.04 LTS (HVM), SSD Volume Type
* Instance Type: m5d.large (recommended for secure and scalable production deployment)
* Use the previously created VPC / security group / subnet / key-pair / ip

Create a configuration for Docker Machine in `/etc/ckan-cloud/.cloud-management-docker-machine.env`:

```
export MACHINE_DRIVER=generic
export GENERIC_IP_ADDRESS=
export GENERIC_SSH_KEY=/etc/ckan-cloud/.cloud-management-id_rsa
export GENERIC_SSH_USER=ubuntu
```

Setup the instance as a Docker Machine

```
source /etc/ckan-cloud/.cloud-management-docker-machine.env && docker-machine create ckan-cloud-management
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

Verify Docker Machine installation:

```
eval $(docker-machine env ckan-cloud-management) &&\
docker version && docker run hello-world
```

## Install Nginx and SSL

Nginx is used for the central entrypoint to the management server and provides SSL using Let's encrypt

```
dm_ssh_sudo() {
    docker-machine ssh ckan-cloud-management sudo "$@"
}
dm_scp_sudo() {
    cat "${1}" | docker-machine ssh ckan-cloud-management -- bash -c 'cat | sudo tee '${2}
}
dm_ssh_sudo apt update -y &&\
dm_ssh_sudo apt install -y nginx certbot &&\
dm_ssh_sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 &&\
dm_ssh_sudo mkdir -p /var/lib/letsencrypt/.well-known &&\
dm_ssh_sudo chgrp www-data /var/lib/letsencrypt &&\
dm_ssh_sudo chmod g+s /var/lib/letsencrypt &&\
dm_scp_sudo nginx/letsencrypt.conf /etc/nginx/snippets/letsencrypt.conf &&\
dm_scp_sudo nginx/ssl.conf /etc/nginx/snippets/ssl.conf &&\
dm_scp_sudo nginx/default.conf /etc/nginx/sites-enabled/default &&\
dm_ssh_sudo systemctl restart nginx
```

Create an SSL certificate using Let's encrypt -

```
LETSENCRYPT_EMAIL=me@company.com
LETSENCRYPT_DOMAIN=cloud-management.my-cluster.com
dm_ssh_sudo certbot certonly --agree-tos --email ${LETSENCRYPT_EMAIL} --webroot -w /var/lib/letsencrypt/ -d ${LETSENCRYPT_DOMAIN} &&\
echo "
  ssl_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/privkey.pem;
  ssl_trusted_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/chain.pem;
" | docker-machine ssh ckan-cloud-management -- bash -c 'cat | sudo tee /etc/nginx/snippets/cloud_management_certs.conf'
```

## Install Rancher

Rancher is used to provision and manage Kubernetes clusters

Create the Rancher data directory:

```
docker-machine ssh ckan-cloud-management sudo mkdir -p /etc/ckan-cloud/rancher
```

Start Rancher (you can use the amazon ec2 public IP domain):

```
eval $(docker-machine env ckan-cloud-management) &&\
docker run -d --name cca-rancher --restart unless-stopped \
               -p 8000:80 \
               -v "/etc/ckan-cloud/rancher:/var/lib/rancher" \
               rancher/rancher:stable
```

Check the logs and make sure Rancher started properly:

```
eval $(docker-machine env ckan-cloud-management) &&\
docker logs -f cca-rancher
```

Add Rancher to NGINX serving on the let's encrypt domain

```
dm_scp_sudo nginx/rancher.conf /etc/nginx/sites-enabled/rancher &&\
echo "  server_name ${LETSENCRYPT_DOMAIN};" | docker-machine ssh ckan-cloud-management -- bash -c 'cat | sudo tee /etc/nginx/snippets/rancher_server_name.conf' &&\
dm_ssh_sudo systemctl restart nginx
```

Open Rancher at the management domain and activate Rancher via the Web UI

## Create a cluster

Use the Rancher UI to create a new Amazon EKS cluster

    * For access key / secret key - you should create a new IAM user which will be used only for this purpose
    * enable Public IP for worker nodes and the Rancher created VPC and subnets
    * Minimum asg of 1-2 nodes, m4.large machine type
    * Wait for cluster to be provisioned, it may take a while...

Follow Rancher logs

```
eval $(docker-machine env ckan-cloud-management) &&\
docker logs -f cca-rancher
```

## Preparing the cluster for CKAN Cloud

Create an Amazon EFS filesystem in the same VPC as the Kubernetes cluster

Assign the EFS mount targets to the same security group as the worker nodes

From the Rancher web-ui:

* Switch to the Global project > catalogs > add catalog:
  * Name: `ckan-cloud-stable`
  * Catalog URL: `https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-helm/master/charts_repository`
* Switch to the ckan-cloud `Default` project > Catalog Apps:
  * Launch `efs` from the `ckan-cloud-stable` catalog
    * Change namespace to use the existing `default` namespace
    * Set the following values:
      * `efsFileSystemID`: Id of Amazon EFS filesystem
      * `efsFileSystemRegion`: The region of the EFS filesystem
* Switch to `Cluster: ckan-cloud` > Storage > Storage classes:
  * Create a storage class called `cca-storage` using Amazon EBS Disk provisioner
* Switch to `Cluster: ckan-cloud` > Launch kubectl:
  * `kubectl create -n default service loadbalancer traefik --tcp=80:80 --tcp=443:443`
* In AWS console: set a security group for the load balancer, alowing access to ports 80, 443 from anywhere
* get the load balancer hostname:
  * rancher > ckan-cloud > launch kubectl: `kubectl -n default get service traefik -o yaml`
  * create CNAME from your custom domain to the load balancer hostname

## Deploy the load balancer

* In Rancher - Switch to the ckan-cloud `Default` project:
  * Resources > Configmaps > Add Config Map
    * Name: `etc-traefik`
    * Namespace: default
    * Config map value:
      * `traefik.toml` = paste the following config (modify the domain)

```
debug = false
defaultEntryPoints = ["http", "https"]

[entryPoints]
    [entryPoints.http]
        address = ":80"

    [entryPoints.https]
        address = ":443"
          [entryPoints.https.tls]

    [ping]
      entryPoint = "http"

    [acme]
      email = your-email@your-domain.com
      storage = "/traefik-acme/acme.json"
      entryPoint = "https"

      [[acme.domains]]
        main = 'example.com'
        sans = ['test1.example.com']

      [acme.dnsChallenge]
        provider = 'route53|cloudflare'

    [accessLog]

    [file]

    [backends]
      [backends.test1]
        [backends.test1.servers.server1]
          url = 'http://nginx.test1'

    [frontends]
      [frontends.test1]
        backend='test1'
        passHostHeader = true
        [frontends.test1.headers]
          SSLRedirect = true
        [frontends.test1.routes.route1]
          rule = 'Host:test1.example.com'
```

* In Rancher - Switch to the ckan-cloud `Default` project:
  * Catalog Apps > Launch `traefik` from the `ckan-cloud-stable` catalog
  * Paste the following values (modify accordingly and create secrets as instructed)

```
dnsProvider=route53|cloudflare
AWS_ACCESS_KEY_ID=
AWS_REGION=
awsSecretName=secret_with_AWS_SECRET_ACCESS_KEY_value
CLOUDFLARE_EMAIL=
CLOUDFLARE_API_KEY=
cfSecretName=secret_with_CLOUDFLARE_API_KEY_value
```

If you edit the configmap to make changes, you need to manually restart the loadbalancer:
* Rancher > ckan-cloud > default > workloads > traefik > redeploy

## Start a CKAN instance

Rancher > ckan-cloud > launch kubectl:

```
CKAN_NAMESPACE=test1 &&\
kubectl create ns "${CKAN_NAMESPACE}" &&\
kubectl --namespace "${CKAN_NAMESPACE}" \
    create serviceaccount "ckan-${CKAN_NAMESPACE}-operator" &&\
kubectl --namespace "${CKAN_NAMESPACE}" \
    create role "ckan-${CKAN_NAMESPACE}-operator-role" --verb list,get,create \
                                                       --resource secrets,pods,pods/exec,pods/portforward &&\
kubectl --namespace "${CKAN_NAMESPACE}" \
    create rolebinding "ckan-${CKAN_NAMESPACE}-operator-rolebinding" --role "ckan-${CKAN_NAMESPACE}-operator-role" \
                                                                     --serviceaccount "${CKAN_NAMESPACE}:ckan-${CKAN_NAMESPACE}-operator"
```

* Rancher > ckan-cloud > Projects/Namespaces > Create project test1 and add the namespace to it
* Rancher > ckan-cloud > test1 > Catalog Apps > Launch ckan chart from ckan-cloud-stable repo
  * Use existing namespace `test`
  * set the following values:

```
siteUrl=https://test1.your-domain.com
replicas=1
nginxReplicas=1
```

* Wait for `test1` workloads to be Running
* Create an admin user:
  * Rancher > ckan-cloud > test1 > workloads > ckan > launch shell:
    * `ckan-paster --plugin=ckan sysadmin -c /etc/ckan/production.ini add admin password=12345678 email=admin@localhost`

Log-in to CKAN at https://test1.your-domain.com
