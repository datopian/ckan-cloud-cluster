# Importing deis instances to ckan-cloud on GKE

## Prepare Gcloud SQL for import via Google Store bucket

Get the service account email for the cloud sql instance (you should be authorized to the relevant Google account)

```
GCLOUD_SQL_INSTANCE_ID=

GCLOUD_SQL_SERVICE_ACCOUNT=`gcloud sql instances describe $GCLOUD_SQL_INSTANCE_ID \
    | python -c "import sys,yaml; print(yaml.load(sys.stdin)['serviceAccountEmailAddress'])" | tee /dev/stderr`
```

Give permissions to the bucket used for importing:

```
GCLOUD_SQL_DUMPS_BUCKET=

gsutil acl ch -u ${GCLOUD_SQL_SERVICE_ACCOUNT}:W gs://${GCLOUD_SQL_DUMPS_BUCKET}/ &&\
gsutil acl ch -R -u ${GCLOUD_SQL_SERVICE_ACCOUNT}:R gs://${GCLOUD_SQL_DUMPS_BUCKET}/
```

## Update ckan-infra secret

should contain the following values:

* POSTGRES_HOST
* POSTGRES_PASSWORD
* POSTGRES_USER
* SOLR_HTTP_ENDPOINT
* SOLR_REPLICATION_FACTOR
* SOLR_NUM_SHARDS
* GCLOUD_SQL_INSTANCE_NAME
* GCLOUD_SQL_PROJECT

## Import DBs from Deis

Connect to the Deis cluster

```
DEIS_KUBECONFIG=/path/to/deis/.kube-config

KUBECONFIG=$DEIS_KUBECONFIG kubectl get nodes
```

Login to the [db-operations pod](https://github.com/ViderumGlobal/ckan-cloud-dataflows/blob/master/db-operations.yaml) on the Deis cluster `backup` namespace

```
KUBECONFIG=$DEIS_KUBECONFIG kubectl -n backup exec -it db-operations -c db -- bash -l
```

Follow the interactive gcloud initialization

Set details of source instance and id for the dump files:

```
DB_URL=
DATASTORE_URL=
SITE_ID=
```

Dump the DBs and upload to cloud storage using the current date and site id (may take a while):

```
source functions.sh
dump_dbs $SITE_ID $DB_URL $DATASTORE_URL && upload_db_dumps_to_storage $SITE_ID
```

Copy the output containing the gs:// urls - you will need them to create the import configuration

Dump files are stored locally in the container and will be removed when db-operations pod is deleted

## Get the instance's solrcloud config name

Get the instance solr config name

```
# you can get the collection name from the instance env vars solr connection url
COLLECTION_NAME=

KUBECONFIG=$DEIS_KUBECONFIG kubectl -n solr exec zk-0 zkCli.sh get /collections/$COLLECTION_NAME
```

The output should contain a config name like `ckan_27_default`

see ckan-cloud-dataflows for importing the configs to searchstax - all configs should be imported already

## Create the import configuration

Create an import configuration yaml and store in cca-operator

```
# the new instance id
INSTANCE_ID=my-imported-instance-id

# urls to db and datastore dumps on google storage bucket
GCLOUD_SQL_DB_DUMP_URL=gs://bucket/path/to/db.dump
GCLOUD_SQL_DATASTORE_DUMP_URL=gs://bucket/path/to/datastore.dump

# solr config name
SOLRCLOUD_COLLECTION_CONFIG_NAME=solr_config_name

# path to yaml file containg the instance env configuration
INSTANCE_ENV_FILE=../ckan-cloud-dataflows/data/deis-instance-config-files/name.yaml

# ckan image
CKAN_IMAGE=

echo '
instance-type: deis-envvars
import:
  gcloud_sql_db_dump_url: '$GCLOUD_SQL_DB_DUMP_URL'
  gcloud_sql_datastore_dump_url: '$GCLOUD_SQL_DATASTORE_DUMP_URL'
  solrcloud_collection_config_name: '$SOLRCLOUD_COLLECTION_CONFIG_NAME'
  ckan_image: '$CKAN_IMAGE'
'"$(cat $INSTANCE_ENV_FILE)"'
' | ./set-instance-values.sh $INSTANCE_ID
```

Login to gcloud (TODO: use default compute service account)

```
source source /google-cloud-sdk/path.bash.inc
gcloud auth login
```

Import and and deploy the instance

```
./import-deis-instance.sh $INSTANCE_ID
```
