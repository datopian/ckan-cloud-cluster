# Contributing to CKAN Cloud Cluster

* Welcome to CKAN Cloud!
* Contributions of any kind are welcome.
* Please [Search for issues across the different CKAN Cloud repositories](https://github.com/search?q=repo%3AViderumGlobal%2Fckan-cloud-docker+repo%3AViderumGlobal%2Fckan-cloud-helm+repo%3AViderumGlobal%2Fckan-cloud-cluster&type=Issues)

## cca-operator instance management development workflow

The following assumes you are running the code from a cloned copy of `ckan-cloud-cluster` reporisotry

The `ckan-cloud-docker` repository should be in relative directory `../ckan-cloud-docker`

see [docs/CCA_OPERATOR.md](docs/CCA_OPERATOR.md) for more details about initial provisioning of the docker machine

Connect to the management docker machine (list available machines using `docker-machine ls`) and set Bash alias

```
CKAN_CLOUD_MANAGEMENT_MACHINE="docker-machine-name"
eval $(docker-machine env "${CKAN_CLOUD_MANAGEMENT_MACHINE}")
alias management-ssh='docker-machine ssh ${CKAN_CLOUD_MANAGEMENT_MACHINE}'
```

Update the server from local repositories

```
./ckan-cloud-cluster.sh init_dev &&\
./ckan-cloud-cluster.sh init_ckan_cloud_docker_dev `pwd`/../ckan-cloud-docker &&\
pushd ../ckan-cloud-docker && docker-compose build cca-operator && popd &&\
echo 'export CCA_OPERATOR_IMAGE="viderum/ckan-cloud-docker:cca-operator-latest"' \
    | management-ssh 'bash -c "cat > /etc/ckan-cloud/.cca_operator-image.env"' &&\
management-ssh sudo ckan-cloud-cluster init_cca_operator &&\
management-ssh sudo ckan-cloud-cluster start_cca_operator_server &&\
docker restart jenkins
```

When making changes to cca-operator scripts and running locally / via Jenkins, you can work in ckan-cloud-docker directory

then run the following snippet to update just cca-operator (while connected to the docker machine):

```
docker-compose build cca-operator
```

See [docs/CCA_OPERATOR.md](docs/CCA_OPERATOR.md) upgrade section to upgrade or reverrt to a published release when you are done developing

## CI/CD

* slack notification is sent on published release
