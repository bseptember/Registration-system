#!/bin/bash
set -e

# Start Keycloak with the specific command
/opt/keycloak/bin/kc.sh $@

# Wait for Keycloak to become operational
until curl -s -o /dev/null https://localhost:8443/; do
  sleep 1
done

# Modify the Postgres schema
echo "Modifying Postgres schema..."
docker exec postgres ./tmp/setup_postgres.sh
wait

echo "Confirming schema alterations"
VERIFY=`docker exec postgres psql -X -A -U postgres -c "\d+ user_attribute" | grep -o "value|character varying|"`

if [ "$VERIFY" = "value|character varying|" ] ; then
    echo "Verified"
else
    echo "Error. Schema not changed. Rerun this script."
fi

# Keep the script running to keep the container alive
tail -f /dev/null
