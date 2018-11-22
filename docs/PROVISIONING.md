# Installing and using the CKAN Cloud Provisioning App on a CKAN Cloud cluster

The provisioning app provides a high-level API and UI to manage and provision CKAN instances.

## Connect to the cca-operator shell

All the following commands should run from the cca-operator shell of a CKAN Cloud cluster

See [Connect to the cca-operator shell](CCA_OPERATOR.md)

## Deploy the provisioning app

Register a subdomain for the provisioning api

```
# a subdomain under the main cluster domain
REGISTER_SUBDOMAIN=cloud-provisioning-api

source functions.sh &&\
LOAD_BALANCER_HOSTNAME=$(kubectl -n default get service traefik -o yaml \
    | python3 -c 'import sys, yaml
ingress = yaml.load(sys.stdin)["status"]["loadBalancer"]["ingress"][0]
print(ingress.get("hostname", ingress.get("ip")))' 2>/dev/null) &&\
cluster_register_sub_domain "${REGISTER_SUBDOMAIN}" "${LOAD_BALANCER_HOSTNAME}"
```

Create the provisioning namespace

```
PROVISIONING_NAMESPACE=provisioning

kubectl create ns $PROVISIONING_NAMESPACE
```

Add to the load balancer

```
DOMAIN="${REGISTER_SUBDOMAIN}.your-domain.com"
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

Restart cca-operator server - this has to be done from the host PC - `docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_cca_operator_server`

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

Create the kubernetes secret

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
