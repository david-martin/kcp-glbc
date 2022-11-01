#!/bin/bash

set -x pipefail

# Setup placements, locations & sample app
export KUBECONFIG=./.kcp/admin.kubeconfig
GLBC_WORKSPACE=root:kuadrant
HOME_WORKSPACE='~'
SCRIPT_DIR=samples/location-api

kubectl kcp workspace ${HOME_WORKSPACE}
kubectl delete -f ${SCRIPT_DIR}/../echo-service/echo.yaml

echo "resetting placement"
kubectl apply -f ${SCRIPT_DIR}/reset-placement.yaml
kubectl delete placement placement-1
kubectl delete placement placement-2

kubectl kcp workspace ${GLBC_WORKSPACE}
echo "deleting locations for sync targets in root:kuadrant workspace"
kubectl delete -f ${SCRIPT_DIR}/locations.yaml

# export KUBECONFIG=~/.kube/config
rm cluster1-site-secret.json
