# pupperware in Kubernetes

## Requirements

The following binaries are required:
https://github.com/roboll/helmfile/releases
https://github.com/helm/helm/releases
https://github.com/databus23/helm-diff
https://kubernetes.io/docs/tasks/tools/install-kubectl

**EXPERIMENTAL**

The k8s YAML files contained within were created with Minikube & Docker for Mac in mind, should be considered experimental, and are not appropriate for most deployments.

## Quick Start

To get started, you will need an Kubernetes cluster at your disposal with [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) configured correctly to communicate with your cluster.
If you do not have a cluster avaiable, [Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/) will allow you to run a single-node Kubernetes cluster on your local machine.

Modify the `DNS_ALT_NAMES` value in [`puppetserver.yaml`](puppetserver.yaml) to contain the DNS names (as a comma-delimited list) of the Kubernetes node that will run the Pupper server pod. If you are
running Kubernetes via Docker for Mac, this will be the FQDN of your Mac. Note that `puppet` is required for Puppet server and PuppetDB to communicate.

```yaml
  - name: DNS_ALT_NAMES
    value: puppet,myworkstation.domain.net
```

Then create the Pupperware resources:

```bash
$ export HIERADATA_URL=https://github.com/SOMEUSER/hieradata.git
$ export PUPPETURL=https://github.com/SOMEUSER/puppet.git
$ helmfile -f puppet.yaml --interactive apply
```

### Connecting Nodes

Kubernetes will expose the Puppet server port (normally TCP port `8140`) on the Kubernetes node using the `NodePort` service type. By default, the TCP port chosen will range from 30000-32767.
Refer to the [Kubernetes documentation on NodePort](https://kubernetes.io/docs/concepts/services-networking/service/#nodeport) for more information.

To find the port number, run `kubectl get svc/puppet`:

```bash
$ kubectl get svc/puppet
NAME       TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
puppet     NodePort   10.106.50.178   <none>        8140:32520/TCP   1m
```

In the example above, the Puppet Server service running on port `8140` has been exposed on the Kubernetes node via port `32520`. Assuming the Kubernetes node's FQDN is
`myworkstation.domain.net`, the following commands will configure a Puppet agent to communicate successfully to the Puppet Server.

```bash
$ puppet config set server myworkstation.domain.net
$ puppet config set masterport 32520
```

## Management

### Running puppet commands

Use the scripts `k8s/bin/puppet` and `k8s/bin/puppetsever` to run commands on the Puppet master. For example, to list all of the certificates using the Puppet 6 CA command,
run `./k8s/bin/puppetserver ca list --all`.

### Running PuppetDB queries

The script `k8s/bin/puppet-query` may be used to run Puppet queries against PuppetDB.

`./k8s/bin/puppet-query 'nodes[certname]{}'`

### Changing postgresql password

The credentials for postgresql are stored within the [`secrets.yaml` file](secrets.yaml) as a base64 encoded string. Replace the string with the desired base64-encoded password.

```bash
$ echo -n "password123" | base64
cGFzc3dvcmQxMjM=
```

### Deleting Pupperware resources

*Warning*: This will completely remove all resources from Kubernetes, including PuppetDB, SSL certificates, and Puppet code.

```bash
$ kubectl delete -f k8s/secrets.yaml -f k8s/postgres.yaml -f k8s/puppetserver.yaml -f k8s/puppetdb.yaml
```

### Running r10k

The script `k8s/bin/r10k` runs r10k on the puppet server

`./k8s/bin/r10k`

### Puppet agent test

The script `k8s/bin/puppet-agent-test` runs a test agent against a working puppet server

`./k8s/bin/puppet-agent-test`

## To-Do

- [ ] Create a more realistic service option using the `LoadBalancer` service type and/or Ingress
- [X] Provide a mechanism to configure r10k & deploy code
- [ ] Provide cron mechanism for r10k command provided externally in bin folder, and hiera repo git pull
- [ ] Create a configuration that uses local volumes to more closely mimic `docker-compose`
- [ ] Use k8s' functions to scale out the infrastructure with additional compile masters (difficult)
