#!/usr/bin/env bash

if [ "${1}" == "install" ]; then
    exit 0

elif [ "${1}" == "script" ]; then
    exit 0

elif [ "${1}" == "deploy" ]; then
    if ! [ -z "${SLACK_TAG_NOTIFICATION_CHANNEL}" ] && ! [ -z "${SLACK_TAG_NOTIFICATION_WEBHOOK_URL}" ]; then
        ! curl -X POST \
               --data-urlencode "payload={\"channel\": \"#${SLACK_TAG_NOTIFICATION_CHANNEL}\", \"username\": \"CKAN Cloud\", \"text\": \"Released ckan-cloud-cluster ${TRAVIS_TAG}\nhttps://github.com/ViderumGlobal/ckan-cloud-cluster/releases/tag/${TRAVIS_TAG}\", \"icon_emoji\": \":female-technologist:\"}" \
               ${SLACK_TAG_NOTIFICATION_WEBHOOK_URL} && exit 1
    fi
    exit 0

fi

echo unexpected failure
exit 1
