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

* [Create a CKAN Cloud management server](docs/MANAGEMENT.md)
* [Create a CKAN Cloud Kubernetes cluster](docs/CLUSTER.md)
* [Install cca-operator on a CKAN Cloud cluster](docs/CCA_OPERATOR.md)

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
cat /etc/ckan-cloud/.cloud-${PROVISIONING_NAMESPACE}-id_rsa.pub | ./add-server-authorized-key.sh
```

Generate the auth keys

```
mkdir -p /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys && pushd /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys &&\
curl -sL https://raw.githubusercontent.com/datahq/auth/master/tools/generate_key_pair.sh | bash &&\
popd
```

Set the GitHub keys

```
echo "*****" > /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/github.key
echo "**************" > /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/github.secret
```

Set connection details to cca-operator SSH (it will use the private ssh key created earlier to authenticate)

```
echo "user@host:port" > /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/instance_manager
```

Recreate the kubernetes secret

```
kubectl -n ${PROVISIONING_NAMESPACE} delete secret api-env;
kubectl -n ${PROVISIONING_NAMESPACE} create secret generic api-env \
    --from-literal=INSTANCE_MANAGER="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/instance_manager)" \
    --from-literal=PRIVATE_SSH_KEY="$(cat /etc/ckan-cloud/.cloud-${PROVISIONING_NAMESPACE}-id_rsa | while read i; do echo ${i}; done)" \
    --from-literal=PRIVATE_KEY="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/private.pem | while read i; do echo ${i}; done)" \
    --from-literal=PUBLIC_KEY="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/public.pem | while read i; do echo ${i}; done)" \
    --from-literal=GITHUB_KEY="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/github.key)" \
    --from-literal=GITHUB_SECRET="$(cat /etc/ckan-cloud/${PROVISIONING_NAMESPACE}-auth-keys/github.secret)"
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
