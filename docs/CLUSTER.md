# CKAN Cloud Kubernetes cluster provisioning and management

The CKAN Cloud Kubernetes Cluster hosts the CKAN instances and related workloads

## Create a CKAN Cloud Kubernets cluster

Install the [management server](MANAGEMENT.md)

Use the Rancher UI to create a cluster, using one of the following methods:

#### Create a Kubernetes cluster using Amazon EKS

Use the Rancher UI to create a new Amazon EKS cluster with the following settings:

* access key / secret key - you should create a new IAM user which will be used only for this purpose
* enable a Public IP for worker nodes
* Use the Rancher created VPC and subnets
* Minimum group of 3 nodes, m4.large machine type
* Wait for cluster to be provisioned, it may take a while...

Create an Amazon EFS filesystem in the same VPC as the Kubernetes cluster

Assign the EFS mount targets to the same security group as the worker nodes

#### Import an existing Google Kubernetes Engine cluster

Create or use an existing cluster from the Google Console web-ui

Should have a minimum of 3 nodes, n1-standard-2 instance type

Use the Rancher UI to import the cluster, follow instructions in the UI for importing GKE cluster

To run the kubectl commands as instructed by Rancher you can start a kubectl shell connected to the cluster from the Google Console web-ui.

## Add the Ckan cloud Helm charts repository

This allows to install charts from the Rancher UI using catalog apps

Rancher > switch to the Global project > catalogs > add catalog:
* Name: `ckan-cloud`
* Catalog URL: `https://raw.githubusercontent.com/ViderumGlobal/ckan-cloud-helm/master/charts_repository`

## Create storage classes

CKAN Cloud cluster needs to have 2 storage classes:

* `cca-storage`: single-user storage, using e.g. Amazon EBS / Google Persistent Disk
* `cca-ckan`: multi-user storage, using e.g. NFS / Amazon EFS

#### Create single-user storage using AWS / GCE / supported providers

Create the single-user storage class -

Rancher > switch to `Cluster: ckan-cloud` > Storage > Storage classes:
* Create a storage class called `cca-storage`
* Use the relevant provisioner (Amazon EBS / Google Persistent Disk)

#### Create multi-user storage using Amazon EFS provisioner

Rancher > switch to the ckan-cloud `Default` project > Catalog Apps:
* Launch `efs` from the `ckan-cloud-stable` catalog
* Change namespace to use the existing `default` namespace
* Set the following values:
  * `efsFileSystemID`: Id of Amazon EFS filesystem
  * `efsFileSystemRegion`: The region of the EFS filesystem

#### Create multi-user storage using NFS server deployed in the cluster

Rancher > Global > Catalogs > Enable Helm Stable catalog

Wait a few minutes until the catalog is synced

Rancher > switch to the ckan-cloud `Default` project > Catalog Apps
* Launch `nfs-server-provisioner`
* Set the following values:
```
persistence.enabled=true
storageClass.name=cca-ckan
```

## Deploy the load balancer to the cluster

Create the load balancer -
* In Rahcner - switch to `Cluster: ckan-cloud` > Launch kubectl:
  * `kubectl create -n default service loadbalancer traefik --tcp=80:80 --tcp=443:443`
* For AWS - set a security group for the load balancer, enabling ports 80 and 443
* get the load balancer hostname / IP:
  * rancher > ckan-cloud > launch kubectl: `kubectl -n default get service traefik -o yaml`
* Set a DNS record from `test1.your-domain.com` to the load balancer hostname / IP

Deploy Traefik - switch to the ckan-cloud `Default` project:
* Resources > Configmaps > Add Config Map
  * Name: `etc-traefik`
  * Namespace: default
* Config map value:
  * `traefik.toml` = paste the following config and modify the values

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
  * Catalog Apps > Launch `traefik` from the `ckan-cloud` catalog
  * Namespace: `default`
  * Paste the following values (modify accordingly and create secrets as instructed)

```
dnsProvider=route53|cloudflare
AWS_ACCESS_KEY_ID=
AWS_REGION=
awsSecretName=secret_with_AWS_SECRET_ACCESS_KEY_value
CLOUDFLARE_EMAIL=
cfSecretName=secret_with_CLOUDFLARE_API_KEY_value
```

You can edit the etc-traefik configmap to make changes to the load balancer

For the changes to take effet, you need to manually restart the loadbalancer:

* Rancher > ckan-cloud > default > workloads > traefik > redeploy

## Deploy Solr Cloud

* Rancher - Switch to the ckan-cloud `Default` project:
  * Catalog Apps > Launch `ckan` from the `ckan-cloud` catalog
  * Name: `solr`
  * Namespace: `ckan-cloud`
  * set values:

```
centralizedInfraOnly=true
dbDisabled=true
usePersistentVolumes=true
storageClassName: cca-storage
solrPersistentDiskSizeGB: 20
```

Start port-forward

```
kubectl -n ckan-cloud port-forward deployment/solr 8983
```

Access solr cloud at http://localhost:8983

If solrcloud is restarted - all collections has to be reloaded via the solr cloud UI or the collections api

**TODO:** auto-reload of collections on solr cloud restart

## Connect to external DB

Create the DB - Postgresql 9.6

* Rancher - Switch to the default namespace:
  * resources > secrets > add secret
  * Name: `ckan-infra`
  * available to a single namespace: `ckan-cloud`
  * values:
```
POSTGRES_HOST=
POSTGRES_USER=
POSTGRES_PASSWORD=
```
