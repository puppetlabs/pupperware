# HELM Chart for Puppet Server

## Prerequisites

### Code Repos

* You must specify your Puppet Control Repo using `puppetserver.puppeturl` variable in the `values.yaml` file or include `--set puppetserver.puppeturl=<your_public_repo>` in the command line of `helm install`. You should specify your separate Hieradata Repo as well using the `hiera.hieradataurl` variable.

* You can also use private repos. Just remember to specify your credentials using `r10k.code.viaSsh.credentials.ssh.value`. You can set similar credentials for your Hieradata Repo.

### Kubernetes Storage Class

Depending on your deployment scenario a certain `StorageClass` object might be required.
In a big K8s megacluster running in the cloud multiple labeled (and/or tainted) nodes in each Availability Zone (AZ) might be present. In such scenario Puppet Server components that use common storage (`puppetserver` and `r10k`) require their volumes to be created in the same AZ. That can be achieved through a custom `StorageClass`.

#### Exemplary definitions

* for Amazon Web Services:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: puppetserver-sc
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
- matchLabelExpressions:
  - key: failure-domain.beta.kubernetes.io/zone
    values:
    - eu-central-1
```

* for Google Cloud Platform:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: puppetserver-sc
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-standard
volumeBindingMode: WaitForFirstConsumer
allowedTopologies:
- matchLabelExpressions:
  - key: failure-domain.beta.kubernetes.io/zone
    values:
    - europe-west3
```

### Common Storage Required for r10k and Puppet Server

Right now we use K8s Cron job to sync the Puppet and Hiera code. We have plans to switch to a sidecar container when we release support for running multiple Puppet compile masters on different K8s nodes. Until then please take advantage of the examples for pod affinity constraint for r10k or the common storage node selector in [values.yaml](values.yaml).

### Load-Balancing Puppet Server

In case a Load Balancer (LB) must sit in front of Puppet Server - please keep in mind that having a Network LB (operating at OSI Layer 4) is preferable.

### NGINX Ingress Controller Configuration

The Ingress resource is disabled by default, but if it is enabled then ssl-passthrough must be used so that puppet agents will get the expected server certificate when connecting to the service.  This feature must be enabled on the Ingress resource itself, but also must be enabled via command line argument to the NGINX Ingress Controller.  More information on that can be found [here](<https://kubernetes.github.io/ingress-nginx/user-guide/cli-arguments/>).

## Migrating from a Bare-Metal Puppet Master

### Auto-Signing Certificate Requests

In general, the easiest way to switch the Puppet Agents from using one Puppet master to another is by enabling the auto-signing of CSRs. By default, that has been pre-enabled in the Puppet Server Docker container. It can be disabled in the Values file by passing an extra environment variable: `AUTOSIGN=false` (in `.Values.puppetserver.extraEnv`).

You will also need to remove the existing certificates in `/etc/puppetlabs/puppet/ssl` on each Puppet agent.

### Using Pre-Generated Puppet Master Certificates

If you prefer not to auto-sign or manually sign the Puppet Agents' CSRs - you can use the same Puppet master and PuppetDB certificates which you used in your bare-metal setup. Please archive into two separate files and place your certificates in the `init/puppet-certs/puppetserver` and `init/puppet-certs/puppetdb` directories and enable their usage in the Values file (`.Values.puppetserver.preGeneratedCertsJob.enabled`).

The content of the two archives should be very similar to:

```console
root@puppet:/# ll /etc/puppetlabs/puppet/ssl/
total 36
drwxr-x--- 4 puppet puppet 4096 Nov 26 20:21 ca/
drwxr-xr-x 2 puppet puppet 4096 Nov 26 20:21 certificate_requests/
drwxr-xr-x 2 puppet puppet 4096 Nov 26 20:21 certs/
-rw-r----- 1 puppet puppet  950 Nov 26 20:21 crl.pem
drwxr-x--- 2 puppet puppet 4096 Nov 26 20:21 private/
drwxr-x--- 2 puppet puppet 4096 Nov 26 20:21 private_keys/
drwxr-xr-x 2 puppet puppet 4096 Nov 26 20:21 public_keys/

root@puppetdb:/opt/puppetlabs/server/data/puppetdb/certs# ls -l
total 20
drwxr-xr-x 2 puppetdb puppetdb 4096 Dec  5 21:49 certificate_requests
drwx------ 2 puppetdb puppetdb 4096 Dec  5 22:36 certs
-rw-r--r-- 1 puppetdb puppetdb  950 Dec  5 21:49 crl.pem
drwx------ 2 puppetdb puppetdb 4096 Dec  5 22:36 private_keys
drwxr-xr-x 2 puppetdb puppetdb 4096 Dec  5 21:49 public_keys
```

Essentially, on your bare-metal Puppet master and PuppetDB instance that's the content of the directories: `/etc/puppetlabs/puppet/ssl` and `/opt/puppetlabs/server/data/puppetdb/certs/`.

The content of the `init/puppet-certs/puppetserver` and `init/puppet-certs/puppetdb` chart's dirs should be similar to:

```console
/repos/xtigyro/puppetserver-helm-chart # ll init/puppet-certs/puppetserver/
total 24
drwxrws--- 2 xtigyro-samba sambashare  4096 Dec  5 22:00 ./
drwxrws--- 4 xtigyro-samba sambashare  4096 Dec  5 21:45 ../
-rw-rw---- 1 xtigyro-samba sambashare    71 Dec  5 21:45 .gitignore
-rw-r--r-- 1 xtigyro-samba sambashare 10013 Dec  5 22:00 puppetserver-certs.gz

/repos/xtigyro/puppetserver-helm-chart # ll init/puppet-certs/puppetdb/
total 24
drwxrws--- 2 xtigyro-samba sambashare  4096 Dec  5 22:00 ./
drwxrws--- 4 xtigyro-samba sambashare  4096 Dec  5 21:45 ../
-rw-rw---- 1 xtigyro-samba sambashare    71 Dec  5 21:45 .gitignore
-rw-r--r-- 1 xtigyro-samba sambashare 10158 Dec  5 22:00 puppetdb-certs.gz
```

> **NOTE**: For more information please check - [README.md](init/README.md). For more general knowledge on the matter you can also read the article - <https://puppet.com/docs/puppet/5.5/ssl_regenerate_certificates.html.>

## Multiple Puppet Compile Masters

To scale Puppet Server for many thousands of nodes, you’ll need to enable multiple Puppet Compile Masters using `.Values.puppetserver.multiCompilers`. These Servers are known as compile masters, and are simply additional load-balanced Puppet Servers that receive catalog requests from agents and synchronize the results with each other.

## Chart Components

* Creates four deployments: Puppet Server, PuppetDB, PosgreSQL, and Puppetboard.
* Creates three services that expose: Puppet Server, PuppetDB, and PostgreSQL.
* Creates a cronjob per configured code repo - up to two.
* Creates secrets to hold credentials for PuppetDB, PosgreSQL, and r10k.

## Installing the Chart

You can install the chart with the release name `puppetserver` as below.

```bash
helm install --namespace puppetserver --name puppetserver ./ --set puppetserver.puppeturl='https://github.com/$SOMEUSER/control-repo.git'
```

> Note - If you do not specify a name, helm will select a name for you.

### Installed Components

You can use `kubectl get` to view all of the installed components.

```console
$ kubectl get --namespace puppetserver all -l release=puppetserver
NAME                                                                  READY   STATUS      RESTARTS   AGE
pod/puppetserver-puppetserver-helm-cha-postgres-5479895bb9-pblfd      1/1     Running     0          10m
pod/puppetserver-puppetserver-helm-cha-puppetdb-8698789c7f-glzdf      1/1     Running     0          10m
pod/puppetserver-puppetserver-helm-cha-puppetserver-d99c99896-99z4h   1/1     Running     0          10m
pod/puppetserver-puppetserver-helm-cha-puppetserver-d99c99896-fhpk4   1/1     Running     0          8m18s
pod/puppetserver-puppetserver-helm-cha-r10k-code-deploy-158610249kr   0/1     Completed   0          6m3s
pod/puppetserver-puppetserver-helm-cha-r10k-code-deploy-1586109f2t2   0/1     Completed   0          4m3s
pod/puppetserver-puppetserver-helm-cha-r10k-code-deploy-158610s2568   0/1     Completed   0          3s
pod/puppetserver-puppetserver-helm-cha-r10k-code-deploy-158610zfdrp   0/1     Completed   0          2m3s

NAME               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
service/postgres   ClusterIP   10.96.197.10    <none>        5432/TCP            10m
service/puppet     ClusterIP   10.96.128.168   <none>        8140/TCP            10m
service/puppetdb   ClusterIP   10.96.114.113   <none>        8080/TCP,8081/TCP   10m

NAME                                                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/puppetserver-puppetserver-helm-cha-postgres       1/1     1            1           10m
deployment.apps/puppetserver-puppetserver-helm-cha-puppetdb       1/1     1            1           10m
deployment.apps/puppetserver-puppetserver-helm-cha-puppetserver   2/2     2            2           10m

NAME                                                                        DESIRED   CURRENT   READY   AGE
replicaset.apps/puppetserver-puppetserver-helm-cha-postgres-5479895bb9      1         1         1       10m
replicaset.apps/puppetserver-puppetserver-helm-cha-puppetdb-8698789c7f      1         1         1       10m
replicaset.apps/puppetserver-puppetserver-helm-cha-puppetserver-d99c99896   2         2         2       10m

NAME                                                                                REFERENCE                                                    TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/puppetserver-puppetserver-helm-cha-autoscaler   Deployment/puppetserver-puppetserver-helm-cha-puppetserver   65%/80%, 0%/80%   1         5         2          10m

NAME                                                                       COMPLETIONS   DURATION   AGE
job.batch/puppetserver-puppetserver-helm-cha-r10k-code-deploy-1586100120   1/1           1s         6m3s
job.batch/puppetserver-puppetserver-helm-cha-r10k-code-deploy-1586100240   1/1           2s         4m3s
job.batch/puppetserver-puppetserver-helm-cha-r10k-code-deploy-1586100360   1/1           2s         2m3s
job.batch/puppetserver-puppetserver-helm-cha-r10k-code-deploy-1586100480   1/1           2s         3s

NAME                                                                SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/puppetserver-puppetserver-helm-cha-r10k-code-deploy   */2 * * * *   False     1        3s              10m
```

## Configuration

The following table lists the configurable parameters of the Puppetserver chart and their default values.

Parameter | Description | Default
--------- | ----------- | -------
`puppetserver.name` | puppetserver component label | `puppetserver`
`puppetserver.image` | puppetserver image | `puppet/puppetserver`
`puppetserver.tag` | puppetserver img tag | `6.9.2`
`puppetserver.resources` | puppetserver resource limits | ``
`puppetserver.extraEnv` | puppetserver additional container env vars |``
`puppetserver.preGeneratedCertsJob.enabled` | puppetserver pre-generated certs |`false`
`puppetserver.preGeneratedCertsJob.jobDeadline` | puppetserver pre-generated certs job deadline in seconds |`60`
`puppetserver.pullPolicy` | puppetserver img pull policy | `IfNotPresent`
`puppetserver.multiCompilers.enabled` | If true, creates multiple Puppetserver compilers | `false`
`puppetserver.multiCompilers.manualScaling.compilers` | If multiple compilers are enabled, this field sets compiler count | `3`
`puppetserver.multiCompilers.autoScaling.enabled` | If true, creates Horizontal Pod Autoscaler | `false`
`puppetserver.multiCompilers.autoScaling.minCompilers` | If autoscaling enabled, this field sets minimum compiler count | `2`
`puppetserver.multiCompilers.autoScaling.maxCompilers` | If autoscaling enabled, this field sets maximum compiler count | `11`
`puppetserver.multiCompilers.autoScaling.cpuUtilizationPercentage` | Target CPU utilization percentage to scale | `50`
`puppetserver.multiCompilers.autoScaling.memoryUtilizationPercentage` | Target memory utilization percentage to scale | `50`
`puppetserver.fqdns.alternateServerNames` | puppetserver alternate fqdns |``
`puppetserver.service.type` | puppetserver svc type | `ClusterIP`
`puppetserver.service.ports` | puppetserver svc exposed ports | `puppetserver`
`puppetserver.service.annotations`| puppetserver svc annotations |``
`puppetserver.service.labels`| puppetserver additional svc labels |``
`puppetserver.service.loadBalancerIP`| puppetserver svc loadbalancer ip |``
`puppetserver.ingress.enabled`| puppetserver ingress creation enabled |`false`
`puppetserver.ingress.annotations`| puppetserver ingress annotations |``
`puppetserver.ingress.extraLabels`| puppetserver ingress extraLabels |``
`puppetserver.ingress.hosts`| puppetserver ingress hostnames |``
`puppetserver.ingress.tls`| puppetserver ingress tls configuration |``
`puppetserver.puppeturl`| puppetserver control repo url |``
`r10k.name` | r10k component label | `r10k`
`r10k.image` | r10k img | `puppet/r10k`
`r10k.tag` | r10k img tag | `3.3.3`
`r10k.pullPolicy` | r10k img pull policy | `IfNotPresent`
`r10k.affinity` | r10k pod assignment affinity |``
`r10k.code.cronJob.schedule` | r10k control repo cron job schedule policy | `*/15 * * * *`
`r10k.code.cronJob.concurrencyPolicy` | r10k control repo cron job concurrency policy | `Forbid`
`r10k.code.cronJob.restartPolicy` | r10k control repo cron job restart policy | `Never`
`r10k.code.cronJob.startingDeadlineSeconds` | r10k control repo cron job starting deadline | `500`
`r10k.code.cronJob.activeDeadlineSeconds` | r10k control repo cron job active deadline | `750`
`r10k.code.resources` | r10k control repo resource limits |``
`r10k.code.extraArgs` | r10k control repo additional container env args |``
`r10k.code.extraEnv` | r10k control repo additional container env vars |``
`r10k.code.viaSsh.credentials.ssh.value`| r10k control repo ssh key file |``
`r10k.code.viaSsh.credentials.known_hosts.value`| r10k control repo ssh known hosts file |``
`r10k.code.viaSsh.credentials.existingSecret`| r10k control repo ssh secret that holds ssh key and known hosts files |``
`r10k.hiera.cronJob.schedule` | r10k hiera data cron job schedule policy | `*/2 * * * *`
`r10k.hiera.cronJob.concurrencyPolicy` | r10k control repo cron job concurrency policy | `Forbid`
`r10k.hiera.cronJob.restartPolicy` | r10k control repo cron job restart policy | `Never`
`r10k.hiera.cronJob.startingDeadlineSeconds` | r10k control repo cron job starting deadline | `500`
`r10k.hiera.cronJob.activeDeadlineSeconds` | r10k control repo cron job active deadline | `750`
`r10k.hiera.resources` | r10k hiera data resource limits |``
`r10k.hiera.extraArgs` | r10k hiera data additional container env args |``
`r10k.hiera.extraEnv` | r10k hiera data additional container env vars |``
`r10k.hiera.viaSsh.credentials.ssh.value`| r10k hiera data ssh key file |``
`r10k.hiera.viaSsh.credentials.known_hosts.value`| r10k hiera data ssh known hosts file |``
`r10k.hiera.viaSsh.credentials.existingSecret`| r10k hiera data ssh secret that holds ssh key and known hosts files |``
`postgres.name` | postgres component label | `postgres`
`postgres.image` | postgres img | `postgres`
`postgres.tag` | postgres img tag | `9.6.16`
`postgres.pullPolicy` | postgres img pull policy | `IfNotPresent`
`postgres.resources` | postgres resource limits |``
`postgres.extraEnv` | postgres additional container env vars |``
`puppetdb.name` | puppetdb component label | `puppetdb`
`puppetdb.image` | puppetdb img | `puppet/puppetdb`
`puppetdb.tag` | puppetdb img tag | `6.9.1`
`puppetdb.pullPolicy` | puppetdb img pull policy | `IfNotPresent`
`puppetdb.resources` | puppetdb resource limits |``
`puppetdb.extraEnv` | puppetdb additional container env vars |``
`puppetdb.credentials.username`| puppetdb username |`puppetdb`
`puppetdb.credentials.value.password`| puppetdb password |`20-char randomly generated`
`puppetdb.credentials.existingSecret`| existing k8s secret that holds puppetdb username and password |``
`puppetboard.enabled` | puppetboard availability | `false`
`puppetboard.name` | puppetboard component label | `puppetboard`
`puppetboard.image` | puppetboard img | `puppet/puppetboard`
`puppetboard.tag` | puppetboard img tag | `0.3.0`
`puppetboard.pullPolicy` | puppetboard img pull policy | `IfNotPresent`
`puppetboard.resources` | puppetboard resource limits |``
`puppetboard.extraEnv` | puppetboard additional container env vars |``
`hiera.name` | hiera component label | `hiera`
`hiera.hieradataurl`| hieradata repo url |``
`hiera.config`| hieradata yaml config |``
`hiera.eyaml.private_key`| hiera eyaml private key |``
`hiera.eyaml.public_key`| hiera eyaml public key |``
`nodeSelector`| Node labels for pod assignment |``
`affinity`| Affinity for pod assignment |``
`tolerations`| Tolerations for pod assignment |``
`priorityClass`| Leverage a priorityClass to ensure your pods survive resource shortages |``
`podAnnotations`| Extra Pod annotations |``
`storage.storageClass`| Storage Class |``
`storage.selector`| PVs/PVCs Selector Config |`false`
`storage.annotations`| Storage annotations |``
`storage.size`| PVCs Storage Size |`100Mi`

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```bash
helm install --namespace puppetserver --name puppetserver ./ --set puppetserver.puppeturl='https://github.com/$SOMEUSER/puppet.git',hiera.hieradataurl='https://github.com/$SOMEUSER/hieradata.git'
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```bash
helm install --namespace puppetserver --name puppetserver ./ -f values.yaml
```

> **Tip**: You can use the default [values.yaml](values.yaml)

## Testing the Deployed Chart Resources

```bash
kubectl port-forward -n puppetserver svc/puppet 8140:8140 &

echo '127.0.0.1 puppet' > ~/.tmp_puppet_hosts
export HOSTALIASES=~/.tmp_puppet_hosts

docker run -dit --network host --name goofy_xtigyro --entrypoint /bin/bash puppet/puppet-agent
docker exec -it goofy_xtigyro bash
puppet agent -t --certname ubuntu-goofy_xtigyro
exit
docker rm -f goofy_xtigyro

docker run -dit --network host --name buggy_xtigyro --entrypoint /bin/bash puppet/puppet-agent
docker exec -it buggy_xtigyro bash
puppet agent -t --certname ubuntu-buggy_xtigyro
exit
docker rm -f buggy_xtigyro

rm ~/.tmp_puppet_hosts
unset HOSTALIASES

jobs | grep 'port-forward' | grep 'puppetserver'
# [1]+  Running                 kubectl port-forward -n puppetserver svc/puppet 8140:8140 &
kill %[job_number_above]
# or execute ¯¯¯\/
## kill %$(jobs | grep 'port-forward' | grep 'puppetserver' | cut -d'+' -f1 | tr -d '[' | tr -d ']')
```

## Chart's Dev Team

* Lead Developer: Miroslav Hadzhiev (miroslav.hadzhiev@gmail.com)
* Developer: Scott Cressi (scottcressi@gmail.com)
* Developer: Morgan Rhodes (morgan@puppet.com)
* Developer: Sean Conley (slconley@gmail.com)
