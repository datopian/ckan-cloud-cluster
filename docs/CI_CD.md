# CKAN Cloud Continuous Integration and Deployment

## Create a continuous-deployment cca-operator role for patching deployments via Travis-CI

Generate an SSH key for this role

```
CCA_OPERATOR_ROLE=continuous-deployment
KEY_COMMENT=travis-ci
KEY_FILE=/etc/ckan-cloud/${CKAN_CLOUD_NAMESPACE}/.${KEY_COMMENT}-id_rsa
MANAGEMENT_SERVER=root@ckan-cloud-management.your-domain.com

ssh-keygen -t rsa -b 4096 -C "${KEY_COMMENT}" -N "" -f "${KEY_FILE}" &&\
cat "${KEY_FILE}.pub" | ssh -p 8022 "${MANAGEMENT_SERVER}" \
    ./cca-operator.sh ./add-server-authorized-key.sh "${CCA_OPERATOR_ROLE}"
```

Restart the cca-operator server

```
docker-machine ssh $(docker-machine active) sudo ckan-cloud-cluster start_cca_operator_server
```

Run the following from the relevant repo directory to add the key file to Travis:

```
GITHUB_REPO_SLUG=repo/other-project

cd ../other-project

travis encrypt-file "${KEY_FILE}" -r "${GITHUB_REPO_SLUG}" -a
```

The travis encrypt-file command modifies `.travis.yml` and adds the openssl command to `before_install` step

Modify the -out param in the openssl command to output the file in `.travis-ci-id_rsa`

Add the environment variables for the patch-deployment command to `.travis.yml`

After building and pushing the image you should have the Docker image value in IMAGE environment variable

Run the following to get the travis script to patch the deployment:

```
echo 'ssh -p 8022 "'${MANAGEMENT_SERVER}'" -o IdentitiesOnly=yes -i ".travis-ci-id_rsa" patch-deployment \
    provisioning api api /etc/ckan-cloud/.provisioning-values.yaml /etc/ckan-cloud/backups/provisioning/values/ \
    apiImage "${IMAGE}"'
```

see [here](https://github.com/ViderumGlobal/ckan-cloud-docker/blob/master/cca-operator/cca-operator.py) for details about the patch-deployment arguments
