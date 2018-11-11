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

Use the Rancher UI to create a new Amazon EKS cluster

    * For access key / secret key - you should create a new IAM user which will be used only for this purpose
    * enable Public IP for worker nodes and the Rancher created VPC and subnets
    * Minimum asg of 1-2 nodes, m4.large machine type
    * Wait for cluster to be provisioned, it may take a while...

Follow Rancher logs

```
./rancher.sh logs -f
```

When the cluster is ready, open the cluster and click on `Kubeconfig File`

copy to clipboard and save in the management server under `/etc/ckan-cloud/.kube-config`

## Verify connection to the cluster

[Install Kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

```
sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

Verify you are connected to the cluster:

```
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
kubectl get nodes
```

## Install Helm

[Install Helm client](https://docs.helm.sh/using_helm/#installing-helm)

```
HELM_VERSION=v2.11.0

curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh &&\
     chmod 700 get_helm.sh &&\
     ./get_helm.sh --version "${HELM_VERSION}" &&\
     helm version --client && rm ./get_helm.sh
```

Create RBAC

```
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
kubectl -n kube-system create serviceaccount tiller &&\
kubectl -n kube-system create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
```

Initialize Helm and restrict for interaction only via the Helm CLI ([source](https://engineering.bitnami.com/articles/helm-security.html))

```
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
helm init --service-account tiller --history-max 2 --upgrade --wait &&\
kubectl -n kube-system delete service tiller-deploy &&\
kubectl -n kube-system patch deployment tiller-deploy --patch 'spec:
  template:
    spec:
      containers:
        - name: tiller
          ports: []
          command: ["/tiller"]
          args: ["--listen=localhost:44134"]' &&\
helm version
```

## Create persistent storage

Create an Amazon EFS filesystem in the same VPC as the Kubernetes cluster

Assign the EFS mount targets to the same security group as the worker nodes

Save the EFS details

```
echo "EFS_FILE_SYSTEM_ID=
EFS_FILE_SYSTEM_REGION=" | sudo tee /etc/ckan-cloud/.efs.env
```

Deploy the EFS provisioner

```
source /etc/ckan-cloud/.efs.env &&\
SET_VALUES="--set efsFileSystemID=${EFS_FILE_SYSTEM_ID} \
            --set efsFileSystemRegion=${EFS_FILE_SYSTEM_REGION}" &&\
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
helm upgrade efs efs --namespace default --install $SET_VALUES --dry-run &&\
helm upgrade efs efs --namespace default --install $SET_VALUES
```

Using Rancher Web UI - Create a storage class called `cca-storage` using Amazon EBS Disk provisioner

## Create a load balancer

Create the load balancer service:

```
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
kubectl create -n default service loadbalancer traefik --tcp=80:80 --tcp=443:443
```

Open AWS Console and get the load balancer hostname

Set a security group for the load balancer, alowing access to ports 80, 443 from anywhere

Create a CNAME from your domains to the load balancer hostname

Create the load balancer configuration in `/etc/ckan-cloud/traefik-values.yaml`:

```
# the ReadWriteMany storage class name
ckanStorageClassName: "cca-ckan"

acmeEmail: ""

# see https://docs.traefik.io/configuration/acme/
acmeDomains: |
  [[acme.domains]]
    main = "example.com"
    sans = ["domain1.example.com", "domain2.example.com"]

# cloudflare or route53
dnsProvider: ""

# route53:
AWS_ACCESS_KEY_ID: ""
AWS_REGION: ""
# kubectl create secret generic -n default traefik-aws --from-literal=AWS_SECRET_ACCESS_KEY=
awsSecretName: traefik-aws

# cloudflare
CLOUDFLARE_EMAIL: ""
# kubectl create secret generic -n default traefik-cf --from-literal=CLOUDFLARE_API_KEY=
cfSecretName: traefik-cf

# see https://docs.traefik.io/configuration/backends/file/

backends: |
  [backends.test1]
    [backends.test1.servers.server1]
      url = http://nginx.test1

  [backends.test2]
    [backends.test2.servers.server1]
      url = http://nginx.test2

frontends: |
  [frontends.test1]
    backend="test1"
    passHostHeader = true
    [frontends.test1.headers]
      SSLRedirect = true
    [frontends.test1.routes.route1]
      rule = "Host:domain1.example.com"

  [frontends.test2]
    backend="test2"
    passHostHeader = true
    [frontends.test2.headers]
      SSLRedirect = true
    [frontends.test2.routes.route1]
      rule = "Host:domain2.example.com"
```

Deploy the load balancer:

```
export KUBECONFIG=/etc/ckan-cloud/.kube-config &&\
helm upgrade traefik traefik --namespace default -if /etc/ckan-cloud/traefik-values.yaml --dry-run &&\
helm upgrade traefik traefik --namespace default -if /etc/ckan-cloud/traefik-values.yaml
```

## Launching worker nodes

see https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html

## Interact with the cca-operator on the ckan-cloud management server

Following commands assume you have a configured SSH host named `ckan-cloud-management` allowing passwordless ssh to the ckan-cloud management server

List instances:

```
ssh ckan-cloud-management /etc/ckan-cloud/cca_operator.sh ./list-instances.sh
```

Delete instance:

```
ssh ckan-cloud-management /etc/ckan-cloud/cca_operator.sh ./delete-instance.sh <INSTANCE_ID>
```

Create instance:

```
# existing instance id to copy the initial values from
export BASE_INSTANCE_ID="demo4"

# the new instance id to create
export NEW_INSTANCE_ID="demo5"
```

Copy and modify existing CKAN instance values yaml, following example uses an interactive editor:

```
ssh ckan-cloud-management sudo bash -c "! [ -e /etc/ckan-cloud/${NEW_INSTANCE_ID}_values.yaml ]" &&\
ssh ckan-cloud-management sudo cp /etc/ckan-cloud/${BASE_INSTANCE_ID}_values.yaml /etc/ckan-cloud/${NEW_INSTANCE_ID}_values.yaml &&\
ssh -t ckan-cloud-management sudo mcedit /etc/ckan-cloud/${NEW_INSTANCE_ID}_values.yaml
```

Review the values:

```
ssh ckan-cloud-management sudo cat /etc/ckan-cloud/${NEW_INSTANCE_ID}_values.yaml
```

Create the instance:

```
ssh ckan-cloud-management /etc/ckan-cloud/cca_operator.sh ./create-instance.sh "${NEW_INSTANCE_ID}"
```

## Install Jenkins

**TODO**
