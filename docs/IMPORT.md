# Importing existing CKAN instances / data to ckan-cloud

**work-in-progress** not stable/ready for use

The import process supports different source types to import from:

* `envvars`: import from an instance configured with ckan-envvars plugin
    * `.env` file contains all the CKAN instance's configuration (includes secret values and service connection details)
    * CKAN Docker image (doesn't have to be a ckan-cloud compatible image)

Importing is done using cca-operator commands

All of the following commands should run from cca-operator shell, see [CCA_OPERATOR.md](CCA_OPERATOR.md) on how to connect to cca-operator shell.

## Create the import configuration

Create an import configuration yaml and store in cca-operator

the following example uses envvars with an example of some of the required details for the import process

```
INSTANCE_ID=my-imported-instance-1

echo '
import-type: envvars
envvars: |
    CKAN_SQLALCHEMY_URL=postgresql://
    CKAN__DATASTORE__READ_URL=postgresql://
    CKAN_SOLR_URL=http://
' | ./set-instance-values.sh $INSTANCE_ID
```

### Import data to the centralized infrastructure

Import the main CKAN DB

```
./import-db.sh $INSTANCE_ID
```




This method allows to import an existing CKAN instance which uses the ckan-envvars plugin

You will need the following details:

* CKAN instance docker image
* `.env` file containing the ckan-envvars configuration (contains secret values)
