# Installing and using cca-operator on a Ckan Cloud cluster

cca-operator is installed on the management server and provides the main low-level entrypoint to manage CKAN Cloud clusters

## Initialize CKAN Cloud

Connect to the management docker machine

```
CKAN_CLOUD_NAMESPACE=my-cloud
eval $(docker-machine env ${CKAN_CLOUD_NAMESPACE}-ckan-cloud-management)
```

Initialize CKAN Cloud on the management server, choose a published release from [here](https://github.com/ViderumGlobal/ckan-cloud-docker/releases)

```
CKAN_CLOUD_DOCKER_VERSION=0.0.6

docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster init_ckan_cloud ${CKAN_CLOUD_DOCKER_VERSION}
```

Alternatively, to sync a local copy of ckan-cloud-docker, provide the path to ckan-cloud-docker:

```
./ckan-cloud-cluster.sh init_ckan_cloud_docker_dev `pwd`/../ckan-cloud-docker
```

Restart Jenkins for the preconfigured jobs to be available:

```
docker restart jenkins
```

## Initialize cca-operator

Log-in to Rancher > cluster: ckan-cloud > cluster > Kubeconfig file

Download the file and save in `/etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.kube-config`

Edit the file and remove the `certificate-authority-data` attribute

Save the kubeconfig on the managmenet server for cca-operator

```
cat /etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.kube-config \
    | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.kube-config"'
```

Save the domain cca-operator secrets in the management server

```
echo '
# using hostname - for AWS
# export CF_ZONE_UPDATE_DATA_TEMPLATE="{\"type\":\"CNAME\",\"name\":\"{{CF_SUBDOMAIN}}\",\"content\":\"{{CF_HOSTNAME}}\",\"ttl\":120,\"proxied\":false}"
# using IP - for GKE
export CF_ZONE_UPDATE_DATA_TEMPLATE="{\"type\":\"A\",\"name\":\"{{CF_SUBDOMAIN}}\",\"content":\"{{CF_HOSTNAME}}\",\"ttl\":120,\"proxied\":false}"

export CF_AUTH_EMAIL=""
export CF_AUTH_KEY=""
export CF_ZONE_NAME="your-domain.com"
export CF_RECORD_NAME_SUFFIX=".your-domain.com"
' | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.cca_operator-secrets.env"'
```

Deploy a cca-operator version of a published release from [here](https://github.com/ViderumGlobal/ckan-cloud-docker/releases)

```
CCA_OPERATOR_VERSION=v0.0.6
# CCA_OPERATOR_VERSION=latest

echo 'export CCA_OPERATOR_IMAGE="viderum/ckan-cloud-docker:cca-operator-'${CCA_OPERATOR_VERSION}'"' \
    | docker-machine ssh $(docker-machine active) 'bash -c "cat > /etc/ckan-cloud/.cca_operator-image.env"'
```

Alternatively - Set CCA_OPERATOR_VERSION to latest and build cca-operator locally while connected to the Docker Machine - `pushd ../ckan-cloud-docker && docker-compose build cca-operator && popd`

Initialize cca-operator

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster init_cca_operator
```

## Install Helm

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster install_helm
```

## Start cca-operator server

Add your personal SSH key to the server

```
cat ~/.ssh/id_rsa.pub | docker-machine ssh $(docker-machine active) /etc/ckan-cloud/cca_operator.sh ./add-server-authorized-key.sh
```

(re)Start the server - must be run after adding authorized keys

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_cca_operator_server
```

Make sure firewall is set to permit port 8022

Run cca-operator commands via ssh to the rancher domain

```
ssh -p 8022 root@$RANCHER_SERVER_NAME ./cca-operator.sh ./list-instances.sh
```

## Upgrade

Upgrade to the required version from [ckan-cloud-docker](https://github.com/ViderumGlobal/ckan-cloud-docker/releases) and [ckan-cloud-cluster](https://github.com/ViderumGlobal/ckan-cloud-cluster/releases)

(Specified version should be without the v prefix - just the version number)

```
CKAN_CLOUD_CLUSTER_VERSION="0.0.6"
CKAN_CLOUD_DOCKER_VERSION="0.0.6"

curl -L https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-cluster/v${CKAN_CLOUD_CLUSTER_VERSION}/ckan-cloud-cluster.sh \
    | bash -s upgrade $CKAN_CLOUD_CLUSTER_VERSION $CKAN_CLOUD_DOCKER_VERSION
```

## Connect to the cca-operator shell

The cca-operator shell allows to run cca-operator and kubectl commands on the cluster.

You can connect using one of the following methods:

* Connecting via the cca-operator ssh server
  * Assuming your personal ssh key is authorized for the management server -
  * `ssh -p 8022 root@ckan-cloud-management.your-domain.com -tt ./cca-operator.sh bash`
* Connecting via Docker Machine
  * Assuming you are connected to the relevant management server Docker Machine
  * `docker-machine ssh $(docker-machine active) -tt /etc/ckan-cloud/cca_operator_shell.sh`

Once you are connected to the shell, enable bash completion:

```
apk add bash-completion && source /etc/profile && source <(kubectl completion bash)
```

You can use the shell to run kubectl commands:

```
kubectl get nodes
```

Or cca-operator commands:

```
./list-instances.sh
```

## Create a limited-access cca-operator ssh user

See [here](https://github.com/ViderumGlobal/ckan-cloud-docker/blob/master/cca-operator/cca-operator.py) for the possible roles.

Generate an SSH key for the role and add to authorized keys for that role

```
CCA_OPERATOR_ROLE=continuous-deployment
KEY_COMMENT=continuous-deployment-role
KEY_FILE=/etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.${KEY_COMMENT}-id_rsa
MANAGEMENT_SERVER=root@ckan-cloud-management.your-domain.com

ssh-keygen -t rsa -b 4096 -C "${KEY_COMMENT}" -N "" -f "${KEY_FILE}" &&\
cat "${KEY_FILE}.pub" | ssh -p 8022 "${MANAGEMENT_SERVER}" \
    ./cca-operator.sh ./add-server-authorized-key.sh "${CCA_OPERATOR_ROLE}"
```

Restart cca-operator server

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_cca_operator_server
```

Try to run a cca-operator command

```
ssh -p 8022 -o IdentitiesOnly=yes -i "${KEY_FILE}" "${MANAGEMENT_SERVER}" ./list-instances.sh
```

The limited access user can only run specific commands, see [here](https://github.com/ViderumGlobal/ckan-cloud-docker/blob/master/cca-operator/cca-operator.py) for details.

If your role is not permitted you will get an error message.

For example, the following command patches the provisioning api deployment for the `continuous-deployment` role

```
NAMESPACE=provisioning
DEPLOYMENT=api
CONTAINER=api
VALUES_FILE=/etc/ckan-cloud/.provisioning-values.yaml
BACKUP_DIR=/etc/ckan-cloud/backups/provisioning/values/
IMAGE_ATTRIB=apiImage
IMAGE=viderum/ckan-cloud-provisioning-api:latest

ssh -p 8022 root@ckan-cloud-management.your-domain.com patch-deployment \
    "${NAMESPACE}" \
    "${DEPLOYMENT}" \
    "${CONTAINER}" \
    "${VALUES_FILE}" \
    "${BACKUP_DIR}" \
    "${IMAGE_ATTRIB}" \
    "${IMAGE}"
```
