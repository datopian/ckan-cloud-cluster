#!/usr/bin/env bash

echo "${VALUES}" > /etc/ckan-cloud/${INSTANCE_ID}_values.yaml &&\
/etc/ckan-cloud/cca_operator.sh ./create-instance.sh ${INSTANCE_ID}
