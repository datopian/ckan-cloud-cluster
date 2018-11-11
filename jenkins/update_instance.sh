#!/usr/bin/env bash

TEMPFILE=`mktemp` &&\
echo "${UPDATE_VALUES}" \
  | python3 -c '
import yaml,sys;
values = yaml.load(open("/etc/ckan-cloud/'${INSTANCE_ID}'_values.yaml"))
values.update(**yaml.load(sys.stdin))
print(yaml.dump(values, default_flow_style=False, allow_unicode=True))
' > $TEMPFILE &&\
cat $TEMPFILE &&\
mv $TEMPFILE /etc/ckan-cloud/${INSTANCE_ID}_values.yaml &&\
/etc/ckan-cloud/cca_operator.sh ./update-instance.sh ${INSTANCE_ID}
