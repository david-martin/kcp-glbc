# POC 1: Ingress on cluster 1, routing to Service on cluster 2 via skupper

* In terminal #1, set up 2 clusters locally with `make local-setup NUM_CLUSTERS=2` 
* In terminal #2, run glbc with appropriate env vars for aws route53 access `(export $(cat ./config/deploy/local/kcp-glbc/controller-config.env | xargs) && export $(cat ./config/deploy/local/kcp-glbc/aws-credentials.env | xargs) && export KUBECONFIG=./tmp/kcp.kubeconfig && ./bin/kcp-glbc)`
* In terminal #3: run `./skupper_install.sh` to install a sample app deployed to 2 locations, setup skupper sites on the 2 kind clusters, link them into a skupper network, and expose the sample service on cluster 2 to the skupper network.

## Open questions

* What establishes/owns the skupper network?
* Is the network transient (ns to ns) or persistent (cluster to cluster)?
* Prevent leaking of services in the physical cluster via NetworkPolicies
* How much skupper CLI logic would we have to do in glbc (e.g. creating proxy services with the right configuration)
* Trigger for proxying is deletion of resources, using soft finalizers. Waiting on KCP changes around namespace deletion to allow using this trigger