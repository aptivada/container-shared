#!/bin/bash
# Make sure you copy the entire shared scripts folder to /usr/local/bin on your container.
set -e
echo "Using $ENVIRONMENT for $SERVICE service"
eval $(aws-env $ENVIRONMENT $SERVICE)
exec $1 "${@:2}"