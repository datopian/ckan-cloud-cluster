#!/usr/bin/env bash

docker build \
  	-t registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${GIT_COMMIT} \
  	multi-tenant-docker/ckan &&\
docker push registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${GIT_COMMIT} &&\
if ! [ -z "${CKAN_CLOUD_BUILD_TAG}" ]; then \
	echo registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${GIT_COMMIT} \
    	> /etc/ckan-cloud/builds/ckan-${CKAN_CLOUD_BUILD_TAG};
fi
