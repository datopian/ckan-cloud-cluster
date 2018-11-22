# Installing and using cca-operator on a Ckan Cloud cluster


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

