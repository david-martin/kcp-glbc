#!/bin/bash
set -e pipefail

source "./utils/.startUtils"

# Setup placements, locations & sample app
export KUBECONFIG=./.kcp/admin.kubeconfig
GLBC_WORKSPACE=root:kuadrant
HOME_WORKSPACE='~'
SCRIPT_DIR=samples/location-api

kubectl kcp workspace ${GLBC_WORKSPACE}
echo "creating locations for sync targets in root:kuadrant workspace"
kubectl apply -f ${SCRIPT_DIR}/locations.yaml

echo "creating apibindings and placements in home workspace"
kubectl kcp workspace ${HOME_WORKSPACE}
kubectl apply -f ./config/apiexports/kubernetes/kubernetes-apibinding.yaml
kubectl apply -f ./config/deploy/local/kcp-glbc/apiexports/glbc/glbc-apibinding.yaml
kubectl apply -f ${SCRIPT_DIR}/placement-1.yaml
kubectl apply -f ${SCRIPT_DIR}/placement-2.yaml
kubectl delete placement default

echo "deploying workload resources in home workspace"
kubectl apply -f ${SCRIPT_DIR}/../echo-service/echo.yaml

export KUBECONFIG=~/.kube/config
wait_for "kubectl --context kind-kcp-cluster-1 get po -A|grep echo" "echo pod in cluster 1" "2m" "5"
wait_for "kubectl --context kind-kcp-cluster-2 get po -A|grep echo" "echo pod in cluster 2" "2m" "5"


echo "Setting up Skupper Site on cluster 1"
# Cluster 1 => west site
CLUSTER1_SVC_NAMESPACE=$(kubectl --context kind-kcp-cluster-1 get svc -A|grep echo | cut -d " " -f1)
kubectl --context kind-kcp-cluster-1 apply -f https://raw.githubusercontent.com/skupperproject/skupper/master/cmd/site-controller/deploy-watch-current-ns.yaml -n ${CLUSTER1_SVC_NAMESPACE}
cat <<EOF | kubectl --context kind-kcp-cluster-1 apply -n ${CLUSTER1_SVC_NAMESPACE} -f -
apiVersion: v1
data:
  cluster-local: "false"
  console: "false"
  edge: "false"
  name: west-site
  router-console: "false"
  service-controller: "true"
  service-sync: "true"
  ingress: "nodeport"
  ingress-host: "172.18.0.2"
kind: ConfigMap
metadata:
  name: skupper-site
EOF
cat <<EOF | kubectl --context kind-kcp-cluster-1 apply -n ${CLUSTER1_SVC_NAMESPACE} -f -
apiVersion: v1
kind: Secret
metadata:
  labels:
    skupper.io/type: connection-token-request
  name: cluster1-site-secret
EOF

wait_for "kubectl --context kind-kcp-cluster-1 get secret cluster1-site-secret -n ${CLUSTER1_SVC_NAMESPACE} -o jsonpath='{.data}'|grep 'ca.crt'" "skupper site link token secret" "2m" "5"
# get link token
kubectl --context kind-kcp-cluster-1 get secret -o json -n ${CLUSTER1_SVC_NAMESPACE} cluster1-site-secret | jq 'del(.metadata.namespace,.metadata.resourceVersion,.metadata.uid) | .metadata.creationTimestamp=null' > ./cluster1-site-secret.json

echo "Setting up Skupper Site on cluster 2"
# Cluster 2 => east site
CLUSTER2_SVC_NAMESPACE=$(kubectl --context kind-kcp-cluster-2 get svc -A|grep echo | cut -d " " -f1)
kubectl --context kind-kcp-cluster-2 apply -f https://raw.githubusercontent.com/skupperproject/skupper/master/cmd/site-controller/deploy-watch-current-ns.yaml -n ${CLUSTER2_SVC_NAMESPACE}
cat <<EOF | kubectl --context kind-kcp-cluster-2 apply -n ${CLUSTER2_SVC_NAMESPACE} -f -
apiVersion: v1
data:
  cluster-local: "false"
  console: "false"
  edge: "false"
  name: east-site
  router-console: "false"
  service-controller: "true"
  service-sync: "true"
  ingress: "nodeport"
  ingress-host: "172.18.0.3"
kind: ConfigMap
metadata:
  name: skupper-site
EOF
# link
echo "Linking skupper sites"
kubectl --context kind-kcp-cluster-2 create -f ./cluster1-site-secret.json -n ${CLUSTER2_SVC_NAMESPACE}

echo "Exposing service in cluster 2 to skupper network"
kubectl config set-context kind-kcp-cluster-2 --namespace=${CLUSTER2_SVC_NAMESPACE}
# TODO DON'T USE SKUPPER CLI
# expose

wait_for "skupper expose service echo --address echo-cluster2-via-skupper" "skupper to expose service" "2m" "5"
#kubectl --context kind-kcp-cluster-2 annotate -n ${CLUSTER2_SVC_NAMESPACE} service echo skupper.io/proxy=http skupper.io/address=echo-cluster2-via-skupper

wait_for "kubectl --context kind-kcp-cluster-1 -n ${CLUSTER1_SVC_NAMESPACE} get svc echo-cluster2-via-skupper" "echo service via skupper to exist" "2m" "5"
echo
echo "=== useful commands:"
echo "kubectl --context kind-kcp-cluster-1 -n ${CLUSTER1_SVC_NAMESPACE} get ingress,deployment,svc,pod -o name"
echo "kubectl --context kind-kcp-cluster-2 -n ${CLUSTER2_SVC_NAMESPACE} get ingress,deployment,svc,pod -o name"
echo "kubectl --context kind-kcp-cluster-1 -n ${CLUSTER1_SVC_NAMESPACE} get ingress echo -o yaml"
echo "kubectl --context kind-kcp-cluster-2 -n ${CLUSTER2_SVC_NAMESPACE} get ingress echo -o yaml"
echo "kubectl --context kind-kcp-cluster-1 -n ${CLUSTER1_SVC_NAMESPACE} logs -f $(kubectl --context kind-kcp-cluster-1 -n ${CLUSTER1_SVC_NAMESPACE} get po -o name | grep echo)"
echo "kubectl --context kind-kcp-cluster-2 -n ${CLUSTER2_SVC_NAMESPACE} logs -f $(kubectl --context kind-kcp-cluster-2 -n ${CLUSTER2_SVC_NAMESPACE} get po -o name | grep echo)"
export KUBECONFIG=./.kcp/admin.kubeconfig
ECHO_HOSTNAME=$(kubectl get ingress echo -o json | jq ".status.loadBalancer.ingress[0].hostname" -r)
echo "watch -n1 \"curl -k --resolve ${ECHO_HOSTNAME}:443:172.18.0.2 https://${ECHO_HOSTNAME}\""
echo "watch -n1 \"curl -k --resolve ${ECHO_HOSTNAME}:443:172.18.0.3 https://${ECHO_HOSTNAME}\""
echo
read -p "Press Enter to trigger migration via migration.kuadrant.dev annotation"
kubectl annotate ingress echo migration.kuadrant.dev/5MivhNIs7DjM7dK95I2K7TpWe7aUGMU4WHqjWn=true

echo
read -p "Press Enter to migrate from cluster 1 to only run on cluster 2"
kubectl delete placement placement-1


# Cleanup
read -p "Press enter to reset cluster"
kubectl delete -f ${SCRIPT_DIR}/../echo-service/echo.yaml

echo "resetting placement"
kubectl apply -f ${SCRIPT_DIR}/reset-placement.yaml
kubectl delete placement placement-2

kubectl kcp workspace ${GLBC_WORKSPACE}
echo "deleting locations for sync targets in root:kuadrant workspace"
kubectl delete -f ${SCRIPT_DIR}/locations.yaml

kubectl kcp workspace ${HOME_WORKSPACE}
