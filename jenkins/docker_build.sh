#!/usr/bin/env bash

docker build \
  	-t ${DOCKER_TAG} \
  	${DOCKER_BUILD_ARGS} &&\
docker push ${DOCKER_TAG} &&\
if ! [ -z "${CKAN_CLOUD_BUILD_TAG}" ]; then \
	echo ${DOCKER_TAG} \
    	> ${CKAN_CLOUD_BUILD_PREFIX}-${CKAN_CLOUD_BUILD_TAG};
fi
