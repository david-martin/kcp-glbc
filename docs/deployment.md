# Deployment

## Cert Manager

The GLBC requires cert manager to be deployed to the [glbc control cluster](#glbc-control-cluster-kubeconfig).

```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.7.1/cert-manager.yaml
kubectl -n cert-manager wait --timeout=300s --for=condition=Available deployments --all
```

## GLBC

Deploy the GLBC using a default configuration. 

```
kubectl apply -k github.com/Kuadrant/kcp-glbc/config/default?ref=main
kubectl -n kcp-glbc wait --timeout=300s --for=condition=Available deployments --all
```

The configuration can be modified after the initial deployment as required, see the [configuration](#configuration) section for more details.

## Local Development

The following describes how to deploy and test the GLBC running on a kind cluster created as part of the local development setup.

### Terminal 1

Run the `local-setup` script to create the test kind clusters and start a local KCP process.

```
$ make local-setup
$ kind get clusters
kcp-cluster-1
kcp-cluster-2
kcp-cluster-glbc-control
```

### Terminal 2

Deploy the GLBC to the local glbc control cluster.

```
kubectl config use-context kind-kcp-cluster-glbc-control
make deploy
kubectl -n kcp-glbc wait --timeout=300s --for=condition=Available deployments --all
kubectl logs -f deployments/kcp-glbc-controller-manager -n kcp-glbc
```

If this is the first time running the `make deploy` command it will generate a set of local configuration files which 
can be used to modify all the configuration described below.

```
$ tree -I '*.yaml|*.template' config/deploy/local/
config/deploy/local/
├── aws-credentials.env
├── controller-config.env
├── glbc.kubeconfig
└── kcp.kubeconfig
```

These files will not be committed and can be modified as required by you, changes can be applied to the local 
deployment by re-running `make deploy`.

### Terminal 3

Test the deployment using the sample service.

```
export KUBECONFIG=.kcp/admin.kubeconfig
kubectl apply -f samples/echo-service/echo.yaml
```

## Configuration

### KCP Kubeconfig (Required)

A secret `secret/kcp-glbc-kcp-kubeconfig` containing the KCP cluster kubeconfig. An empty secret is created by default 
during installation, but can be replaced with:  

```
kubectl -n kcp-glbc create secret generic kcp-glbc-kcp-kubeconfig --from-file=kubeconfig=$(KCP_KUBECONFIG)
```

### GLBC Control Cluster Kubeconfig (Required)

A secret `secret/kcp-glbc-glbc-kubeconfig` containing the GLBC control clusters kubeconfig. This is the cluster running cert manager. 
An empty secret is created by default during installation, but can be replaced with:

```
kubectl -n kcp-glbc create secret generic kcp-glbc-glbc-kubeconfig --from-file=kubeconfig=$(GLBC_KUBECONFIG)
```

### AWS Credentials (Optional) 

A secret  `secret/kcp-glbc-aws-credentials` containing AWS access key and secret. This is only required if `GLBC_DNS_PROVIDER` is set to `aws`.
The credentials must have permissions to create/update/delete records in the hosted zone set in `AWS_DNS_PUBLIC_ZONE_ID`, and the
domain set in `GLBC_DOMAIN` corresponds to the public zone id. An empty secret is created by default during installation, 
but can be replaced with:

```
kubectl -n kcp-glbc create secret generic kcp-glbc-aws-credentials \
--from-literal=AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} \
--from-literal=AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
```

### GLBC Controller Options (Optional)

A config map `configmap/kcp-glbc-controller-config` containing GLBC configuration options. A config map is created by 
default during installation containing the default values, but can be replaced by editing the config map:

```
kubectl -n kcp-glbc edit configmap kcp-glbc-controller-config
```

| Annotation | Description | Default value |
| ---------- | ----------- | ------------- |
| `AWS_DNS_PUBLIC_ZONE_ID` |  AWS hosted zone id where route53 records will be created (default is dev.hcpapps.net) | Z08652651232L9P84LRSB |
| `GLBC_DNS_PROVIDER` |  The dns provider to use, one of [aws, fake] | fake |
| `GLBC_DOMAIN` |  The domain to use when exposing ingresses via glbc | dev.hcpapps.net |
| `GLBC_ENABLE_CUSTOM_HOSTS` | Allow custom hosts in glbc managed ingresses | false |
| `GLBC_TLS_PROVIDED` | Generate TLS certs for glbc managed hosts | false |
| `GLBC_TLS_PROVIDER` | TLS Cert provider to use, one of [le-staging, le-production] | le-staging |
| `HCG_LE_EMAIL` | EMail address to use during LE cert requests | kuadrant-dev@redhat.com |
| `GLBC_LOGICAL_CLUSTER_TARGET` | logical cluster to target | root:rh-sso-15897946:glbc |

### Applying configuration changes

Any of the described configurations can be modified after the initial creation of the resources, the deploymnet will however 
need to be restarted after each change in order for them to come into affect.

`kubectl rollout restart deployment/kcp-glbc-controller-manager -n kcp-glbc`