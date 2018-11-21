# CKAN Cloud Cluster Provisioning and Management

Documentation and code for provisioning and running CKAN Cloud clusters.

## Setup the CKAN Cloud management server

The CKAN Cloud management server provisions and manages CKAN Cloud clusters.

* [Install Docker Machine](https://docs.docker.com/machine/install-machine/)
  * Following works on Linux which has Docker already installed:

```
base=https://github.com/docker/machine/releases/download/v0.14.0 &&
curl -L $base/docker-machine-$(uname -s)-$(uname -m) >/tmp/docker-machine &&
sudo install /tmp/docker-machine /usr/local/bin/docker-machine
```

Verify:

```
docker-machine version
```

Set a unique CKAN Cloud namespace name for this cloud management server and create the configuration directory

```
CKAN_CLOUD_NAMESPACE=my-cloud
mkdir -p /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}
```

Generate an SSH key to access the machine

```
ssh-keygen -t rsa -b 4096 -C "admin@ckan-cloud-management" -f /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.cloud-management-id_rsa
```

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

Initialize the instance as a Docker Machine (using the generic SSH driver)

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

Activate the machine

```
eval $(docker-machine env ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management)
```

Verify Docker Machine installation:

```
docker version && docker run hello-world
```

Initialize ckan-cloud-cluster

```
CKAN_CLOUD_CLUSTER_VERSION=0.0.2

curl -L https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-cluster/v${CKAN_CLOUD_CLUSTER_VERSION}/ckan-cloud-cluster.sh \
    | bash -s init $CKAN_CLOUD_CLUSTER_VERSION
```

If you want to install latest dev version of ckan-cloud-cluster -
clone the code, and run the following from the ckan-cloud-cluster project directory: `./ckan-cloud-cluster.sh init_dev`

## Install Nginx and SSL

Install and configure Nginx and Let's Encrypt (will delete any existing configurations)

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster install_nginx_ssl
```

Get the server's hostname:

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster get_aws_public_hostname
```

Set DNS CNAME records for the following subdomains to this IP:

* `ckan-cloud-management.your-domain.com` - serves Rancher
* `ckan-cloud-jenkins.your-domain.com` - serves Jenkins

(for maximal security, add a CAA record: `your-domain.com. CAA 128 issue "letsencrypt.org"`)

Register the SSL certificates

```
LETSENCRYPT_EMAIL=your@email.com
CERTBOT_DOMAINS="ckan-cloud-management.your-domain.com,ckan-cloud-jenkins.your-domain.com"
LETSENCRYPT_DOMAIN=ckan-cloud-management.your-domain.com

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster setup_ssl ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN}
```

## Deploy Rancher

Start Rancher

```
SERVER_NAME=ckan-cloud-management.your-domain.com

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_rancher ${SERVER_NAME}
```

Activate via the web-ui at https://ckan-cloud-management.your-domain.com/

## Create a cluster for CKAN Cloud

Use the Rancher UI to create a new Amazon EKS cluster

    * For access key / secret key - you should create a new IAM user which will be used only for this purpose
    * enable Public IP for worker nodes and the Rancher created VPC and subnets
    * Minimum asg of 1-2 nodes, m4.large machine type
    * Wait for cluster to be provisioned, it may take a while...

Create an Amazon EFS filesystem in the same VPC as the Kubernetes cluster

Assign the EFS mount targets to the same security group as the worker nodes

From the Rancher web-ui:

Install the Helm charts repo - switch to the Global project > catalogs > add catalog:
* Name: `ckan-cloud-stable`
* Catalog URL: `https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-helm/master/charts_repository`

Deploy the efs-provisioner - switch to the ckan-cloud `Default` project > Catalog Apps:
* Launch `efs` from the `ckan-cloud-stable` catalog
* Change namespace to use the existing `default` namespace
* Set the following values:
  * `efsFileSystemID`: Id of Amazon EFS filesystem
  * `efsFileSystemRegion`: The region of the EFS filesystem

Create the Amazon EBS Disk provisioner - switch to `Cluster: ckan-cloud` > Storage > Storage classes:
* Create a storage class called `cca-storage` using Amazon EBS Disk provisioner

## Deploy the load balancer

Create the load balancer -
* In Rahcner - switch to `Cluster: ckan-cloud` > Launch kubectl:
  * `kubectl create -n default service loadbalancer traefik --tcp=80:80 --tcp=443:443`
* In AWS console - set a security group for the load balancer, alowing access to ports 80, 443 from anywhere
* get the load balancer hostname:
  * rancher > ckan-cloud > launch kubectl: `kubectl -n default get service traefik -o yaml`
* create CNAME from `test1.your-domain.com` to the load balancer hostname

Deploy Traefik - switch to the ckan-cloud `Default` project:
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
      email = "your-email@your-domain.com"
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

You can edit the etc-traefik configmap to make change to the load balancer

For the changes to take effet, you need to manually restart the loadbalancer:

* Rancher > ckan-cloud > default > workloads > traefik > redeploy

## Deploy Jenkins

Start Jenkins

```
SERVER_NAME=ckan-cloud-jenkins.your-domain.com
JENKINS_IMAGE=viderum/ckan-cloud-docker:jenkins-v0.0.2

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_jenkins ${SERVER_NAME} ${JENKINS_IMAGE}
```

Get the admin password

```
docker-machine ssh $(docker-machine active) sudo cat /var/jenkins_home/secrets/initialAdminPassword
```

Activate via the web-ui at https://ckan-cloud-jenkins.your-domain.com

## Initialize CKAN Cloud

Initialize:

```
CKAN_CLOUD_DOCKER_VERSION=0.0.3

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster init_ckan_cloud ${CKAN_CLOUD_DOCKER_VERSION}
```

To sync local copy of ckan-cloud-docker to the server:

```
./ckan-cloud-cluster.sh init_ckan_cloud_docker_dev `pwd`/../ckan-cloud-docker
```

Log-in to Rancher > top right profile image > API & Keys > generate an API key

Create a kubeconfig for cca-operator using the Rancher API key values:

```
CLUSTER_NAME=ckan-cloud
RANCHER_API_CLUSTER_URL=https://ckan-cloud-management.your-domain.com/k8s/clusters/c-zzzzz
RANCHER_API_ACCESS_KEY="token-xxxxx"
RANCHER_API_BEARER_TOKEN="token-xxxxx:yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"

echo 'apiVersion: v1
kind: Config
clusters:
- name: "'${CLUSTER_NAME}'"
  cluster:
    server: "https://ckan-cloud-management.datagov.us/k8s/clusters/c-5mgh6"
    api-version: v1
users:
- name: "'${RANCHER_API_ACCESS_KEY}'"
  user:
    token: "'${RANCHER_API_BEARER_TOKEN}'"
contexts:
- name: "'${CLUSTER_NAME}'"
  context:
    user: "'${RANCHER_API_ACCESS_KEY}'"
    cluster: "'${CLUSTER_NAME}'"
current-context: "'${CLUSTER_NAME}'"' | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.kube-config"'
```

Initialize cca-operator

```
# set cloudflare settings to register sub-domains
echo 'export CF_AUTH_EMAIL=""
export CF_AUTH_KEY=""
export CF_ZONE_NAME=""' \
    | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.cca_operator-secrets.env"'

# set the Docker image to use for cca-operator
echo 'export CCA_OPERATOR_IMAGE="viderum/ckan-cloud-docker:cca-operator-v0.0.2"' \
    | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.cca_operator-image.env"'

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster init_cca_operator
```

Install Helm:

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster install_helm
```

Reload the Jenkins jobs - Jenkins web-ui > manage jenkins > reload configurations from disk

Manage CKAN instances using the cluster administration Jenkins jobs

## Using cca-operator CLI

Run a cca-operator command:

```
docker-machine ssh $(docker-machine active) /etc/ckan-cloud/cca_operator.sh ./list-instances.sh
```

Run cca-operator interactive shell:

```
docker-machine ssh $(docker-machine active) -tt /etc/ckan-cloud/cca_operator_shell.sh
$ ./list-instances.sh
$ kubectl get nodes
```

To use a development version of cca-operator - build cca-operator while connected to the Docker Machine:

```
# change to the ckan-cloud-docker project directory
cd ../ckan-cloud-docker

# Ensure you are connected to the Docker Machine
CKAN_CLOUD_NAMESPACE=my-cloud
eval $(docker-machine env ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management)

# build
docker-compose build cca-operator
```

Set cca-operator to use the latest image (which is the default image built by the docker-compose):

```
echo 'export CCA_OPERATOR_IMAGE="viderum/ckan-cloud-docker:cca-operator-latest"' \
    | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.cca_operator-image.env"'
```

You can now run cca-operator commands / shell and it will use the latest locally built copy

## Start cca-operator server

Add your SSH key to the server

```
cat ~/.ssh/id_rsa.pub | docker-machine ssh $(docker-machine active) /etc/ckan-cloud/cca_operator.sh ./add-server-authorized-key.sh
```

Start the server, re-run after adding authorized keys

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_cca_operator_server
```

Make sure firewall is set to permit port 8022

Get the hostname

```
CCA_OPERATOR_SSH_HOST=`docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster get_aws_public_hostname`
```

Run cca-operator commands via ssh

```
ssh -p 8022 root@$CCA_OPERATOR_SSH_HOST ./cca-operator.sh ./list-instances.sh
```

## Upgrade

Upgrade to the required version from [ckan-cloud-docker](https://github.com/ViderumGlobal/ckan-cloud-docker/releases) and [ckan-cloud-cluster](https://github.com/ViderumGlobal/ckan-cloud-cluster/releases)

(Specified version should be without the v prefix - just the version number)

```
CKAN_CLOUD_CLUSTER_VERSION="0.0.2"
CKAN_CLOUD_DOCKER_VERSION="0.0.3"

curl -L https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-cluster/v${CKAN_CLOUD_CLUSTER_VERSION}/ckan-cloud-cluster.sh \
    | bash -s upgrade $CKAN_CLOUD_CLUSTER_VERSION $CKAN_CLOUD_DOCKER_VERSION
```

## Deploy the provisioning app

Start cca-operator shell

Using the cca-operator server via ssh (assuming your ssh key is authorized)

```
CCA_OPERATOR_SSH_HOST="ckan-cloud-management.your-domain.com"

ssh -p 8022 root@$CCA_OPERATOR_SSH_HOST -tt ./cca-operator.sh bash
```

Alternatively, using docker-machine

```
docker-machine ssh $(docker-machine active) -tt /etc/ckan-cloud/cca_operator_shell.sh
```

All the following commands should run from the cca-operator shell

(optional) Enable kubectl bash completion

```
apk add bash-completion && source /etc/profile && source <(kubectl completion bash)
```

Register a subdomain for the provisioning api

```
# a subdomain under the main cluster domain
REGISTER_SUBDOMAIN=cloud-provisioning-api

source functions.sh &&\
LOAD_BALANCER_HOSTNAME=$(kubectl -n default get service traefik -o yaml \
    | python3 -c 'import sys, yaml; print(yaml.load(sys.stdin)["status"]["loadBalancer"]["ingress"][0]["hostname"])' 2>/dev/null) &&\
cluster_register_sub_domain "${REGISTER_SUBDOMAIN}" "${LOAD_BALANCER_HOSTNAME}"
```

Create the provisioning namespace

```
PROVISIONING_NAMESPACE=provisioning

kubectl create ns $PROVISIONING_NAMESPACE
```

Add to the load balancer

```
DOMAIN="cloud-provisioning-api.your-domain.com"
WITH_SANS_SSL="1"
INSTANCE_ID="cloud-provisioning-api"
SERVICE_NAME=api
SERVICE_PORT=8000
SERVICE_NAMESPACE=$PROVISIONING_NAMESPACE

source functions.sh &&\
add_domain_to_traefik "${DOMAIN}" "${WITH_SANS_SSL}" "${INSTANCE_ID}" "${SERVICE_NAME}" "${SERVICE_PORT}" "${SERVICE_NAMESPACE}"
```

Generate an ssh key to allow the provisioning app to access cca-operator

```
ssh-keygen -t rsa -b 4096 -C "admin@ckan-cloud-${PROVISIONING_NAMESPACE}" -N "" -f /etc/ckan-cloud/.cloud-${PROVISIONING_NAMESPACE}-id_rsa
```

Register the key in the cca-operator server

```
cat /etc/ckan-cloud/.cloud-${PROVISIONING_NAMESPACE}-id_rsa | ./add-server-authorized-key.sh
```

Generate the auth keys

```
mkdir -p /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys && pushd /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys &&\
curl -sL https://raw.githubusercontent.com/datahq/auth/master/tools/generate_key_pair.sh | bash &&\
popd
```

Recreate the kubernetes secret

```
kubectl -n ${PROVISIONING_NAMESPACE} delete secret api-env;
kubectl -n ${PROVISIONING_NAMESPACE} create secret generic api-env \
    --from-literal=INSTANCE_MANAGER=root@cca-operator \
    --from-literal=PRIVATE_SSH_KEY="$(cat /etc/ckan-cloud/.cloud-${PROVISIONING_NAMESPACE}-id_rsa | while read i; do echo ${i}; done)" \
    --from-literal=PRIVATE_KEY="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/private.pem | while read i; do echo ${i}; done)" \
    --from-literal=PUBLIC_KEY="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/public.pem | while read i; do echo ${i}; done)" \
    --from-literal=GITHUB_KEY="" \
    --from-literal=GITHUB_SECRET=""
```

Create the provisioning chart values

```
echo "apiImage: viderum/ckan-cloud-provisioning-api:latest
apiDbImage: postgres
apiResources: '{\"requests\": {\"cpu\": \"50m\", \"memory\": \"200Mi\"}, \"limits\": {\"memory\": \"800Mi\"}}'
apiDbResources: '{\"requests\": {\"cpu\": \"50m\", \"memory\": \"200Mi\"}, \"limits\": {\"memory\": \"800Mi\"}}'
apiExternalAddress: https://cloud-provisioning-api.your-domain.com
usePersistentVolumes: true
storageClassName: cca-storage
ckanStorageClassName: cca-ckan
apiDbPersistentDiskSizeGB: 10
apiEnvFromSecret: api-env" > /etc/ckan-cloud/.${PROVISIONING_NAMESPACE}-values.yaml
```

Initialize client-side Helm and add the charts repo

```
helm init --client-only &&\
helm repo add ckan-cloud https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-helm/master/charts_repository
```

Deploy the provisioning chart

choose from https://github.com/ViderumGlobal/ckan-cloud-helm/releases
or use 0.0.0 for manually built dev version (see [here](https://github.com/ViderumGlobal/ckan-cloud-helm/blob/master/CONTRIBUTING.md#updating-the-helm-charts-repo-for-development))

```
PROVISIONING_CHART_VERSION="0.0.0"

helm upgrade --namespace ${PROVISIONING_NAMESPACE} "ckan-cloud-${PROVISIONING_NAMESPACE}" \
             ckan-cloud/provisioning --version v${PROVISIONING_CHART_VERSION} --install \
             --force -f /etc/ckan-cloud/.${PROVISIONING_NAMESPACE}-values.yaml
```

Get the provisioning secrets

```
PROVISIONING_SECRETS=`get_secrets_json "-n provisioning api-env"`
for KEY in INSTANCE_MANAGER PRIVATE_SSH_KEY PRIVATE_KEY PUBLIC_KEY GITHUB_KEY GITHUB_SECRET
do echo "###### ${KEY} ######"; echo; get_secret_from_json "${PROVISIONING_SECRETS}" $KEY; echo; echo; done
```
