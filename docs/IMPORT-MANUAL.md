# Manual import of instances to CKAN Cloud


## Prepare centralized infra

ssh to cca-operator

```
ssh -p 8022 root@cloud-management.ckan.io -tt ./cca-operator.sh bash
```

Create the dbs

```
# choose a unique instance id as a base for the db and user names, as well as passwords for the created users
INSTANCE_ID=
DB_PASSWORD=
DS_RW_PASSWORD=
DS_RO_PASSWORD=

# connection details to the centralized DB
PGHOST=
PGUSER=
export PGPASSWORD=

create_db $PGHOST $PGUSER $INSTANCE_ID $DB_PASSWORD &&\
create_datastore_db $PGHOST $PGUSER $INSTANCE_ID ${INSTANCE_ID}-datastore $DS_RW_PASSWORD ${INSTANCE_ID}-datastore-ro $DS_RO_PASSWORD
```

Create the solrcloud collection

```
INSTANCE_ID=

SOLRCLOUD_POD_NAME=$(kubectl -n ckan-cloud get pods -l "app=solr" -o 'jsonpath={.items[0].metadata.name}')

kubectl -n ckan-cloud exec $SOLRCLOUD_POD_NAME -- sudo -u solr bin/solr \
    create_collection -c ${INSTANCE_ID} -d ckan_default -n ckan_default
```


## Prepare Gcloud SQL for import via Google Store bucket

Should be done only once for each Gcloud instance / stsorage combination

Get the service account email for the cloud sql instance

```
GCLOUD_SQL_SERVICE_ACCOUNT=`gcloud sql instances describe ckan-cloud-staging \
    | python -c "import sys,yaml; print(yaml.load(sys.stdin)['serviceAccountEmailAddress'])" | tee /dev/stderr`
```

Give permissions to the bucket used for importing:

```
gsutil acl ch -u ${GCLOUD_SQL_SERVICE_ACCOUNT}:W gs://viderum-deis-backups/ &&\
gsutil acl ch -R -u ${GCLOUD_SQL_SERVICE_ACCOUNT}:R gs://viderum-deis-backups/
```


## DB Migration to Google Cloud SQL

Log-in to db-operations pod (see [here](https://github.com/ViderumGlobal/ckan-cloud-dataflows/blob/master/db-operations.yaml) to deploy)

```
KUBECONFIG=$DEIS_KUBECONFIG kubectl -n backup exec -it db-operations -c db -- bash -l
```

Follow the interactive gcloud initialization

Dump the DBs in the recommended cloud sql format:

```
dump_dbs() {
    local _site_id=$1
    local _db_url=$2
    local _ds_url=$3
    local _db_dump="${_site_id}.`date +%Y%m%d`.dump.sql"
    local _ds_dump="${_site_id}-datastore.`date +%Y%m%d`.dump.sql"
    pg_dump -d $_db_url --format=plain --no-owner --no-acl \
        | sed -E 's/(DROP|CREATE|COMMENT ON) EXTENSION/-- \1 EXTENSION/g' > $_db_dump &&\
    pg_dump -d $_ds_url --format=plain --no-owner --no-acl \
        | sed -E 's/(DROP|CREATE|COMMENT ON) EXTENSION/-- \1 EXTENSION/g' > $_ds_dump &&\
    echo Great Success! && echo $_db_dump && echo $_ds_dump && return 0
    echo Failed && return 1
}

dump_dbs <SITE_ID_FOR_DUMP_FILE_NAMES> <DB_URL> <DATASTORE_URL>
```

Upload the dumps to google storage

```
upload_db_dumps_to_storage() {
    local _site_id=$1
    local _db_dump="${_site_id}.`date +%Y%m%d`.dump.sql"
    local _ds_dump="${_site_id}-datastore.`date +%Y%m%d`.dump.sql"
    gsutil cp ./${_db_dump} gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/ &&\
    gsutil cp ./${_ds_dump} gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/ &&\
    echo Great Success && echo "gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/${_db_dump}" &&\
                          echo "gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/${_ds_dump}" &&\
                          return 0
    echo Failed && return 1
}

upload_db_dumps_to_storage <SITE_ID_FOR_DUMP_FILE_NAMES>
```

Import

```
import_dumps_to_cloudsql() {
    local _site_id=$1
    local _db_name=$2
    local _ds_name=$3
    local _db_dump="${_site_id}.`date +%Y%m%d`.dump.sql"
    local _ds_dump="${_site_id}-datastore.`date +%Y%m%d`.dump.sql"
    gcloud sql import sql ckan-cloud-staging "gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/${_db_dump}" --database=$_db_name &&\
    gcloud sql import sql ckan-cloud-staging "gs://viderum-deis-backups/postgres/$(date +%Y%m%d)/${_ds_dump}" --database=$_ds_name &&\
    echo Great Success && echo "imported DB names: ${_site_id} ${_site_id}-datastore" && return 0
    echo Failed && return 1
}

import_dumps_to_cloudsql <SITE_ID_FOR_FILES> <SITE_DB_NAME> <DATASTORE_DB_NAME>
```

## Deploy

Enable gitlab-ci for the relevant instance repo (see [here](https://gitlab.com/viderum/cloud-navitasventures/blob/master/.gitlab-ci.yml))

Build the image to Gitlab private docker registry

Using Rancher you can add a docker pull secret to enable the cluster to get the image

Create a namespace for the instance with a configmap containing the .env file from Gitlab

Modify configmap to point to the new infrastructure

Deploy the image - can be done using Rancher UI, you only need the image and environment from the configmap.
