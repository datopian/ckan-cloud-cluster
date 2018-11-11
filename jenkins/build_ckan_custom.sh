#!/usr/bin/env bash

cd multi-tenant-docker &&\
docker-compose -f docker-compose.yaml build ckan &&\
docker tag ckan-multi-ckan registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${DOCKER_IMAGE_TAG} &&\
docker push registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${DOCKER_IMAGE_TAG} &&\
echo "
Docker image:

registry.gitlab.com/datopian/datagov-ckan-multi:ckan-${DOCKER_IMAGE_TAG}

"
