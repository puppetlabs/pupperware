# HELM Chart for Puppet Server

## Prerequisites

### Code Repos

* You must specify your Puppet Control Repo using `puppetserver.puppeturl` variable in the `values.yaml` file or include `--set puppetserver.puppeturl=<your_public_repo>` in the command line of `helm install`. You should specify your separate Hieradata Repo as well using the `hiera.hieradataurl` variable.

* You can also use private repos. Just remember to specify your credentials using `r10k.viaHttps.credentials` or `r10k.viaSsh.credentials`. You can set similar credentials for your Hieradata Repo.

### Kubernetes Storage Class

Depending on your deployment scenario a certain `StorageClass` object might be required.
In a big K8s megacluster running in the cloud multiple labeled (and/or tainted) nodes in each Availability Zone (AZ) might be present. In such scenario Puppet Server components that use common storage (`puppetserver` and `r10k`) require their volumes to be created in the same AZ. That can be achieved through a custom `StorageClass`.

Exemplary definition:

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
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
    - us-east-1d
```

### Load-Balancing Puppet Server

In case a Load Balancer (LB) must sit in front of Puppet Server - please keep in mind that having a Network LB (operating at OSI Layer 4) is preferable.

## Chart Components

* Creates four deployments: Puppet Server, PuppetDB, PosgreSQL, and Puppetboard.
* Creates three Kubernetes Services that expose: Puppet Server, PuppetDB, and PostgreSQL.
* Creates Secrets to hold credentials for PuppetDB, PosgreSQL, and r10k.

## Installing the Chart

You can install the chart with the release name `puppetserver` as below.

```bash
helm install --namespace puppetserver --name puppetserver ./ --set puppetserver.puppeturl='https://github.com/$SOMEUSER/control-repo.git'
```

> Note - If you do not specify a name, helm will select a name for you.

### Installed Components

You can use `kubectl get` to view all of the installed components.

```console
$ kubectl get --namespace puppetserver all -l app=puppetserver
NAME                                READY   STATUS      RESTARTS   AGE
pod/postgres-584d75d8b-gw8n6        1/1     Running     0          31m
pod/puppetdb-5f6fd6df7d-fqbc2       1/1     Running     0          31m
pod/puppetserver-54f889b9c5-r7gm9   1/1     Running     0          31m
pod/r10k-deploy-1573860480-5nnp9    0/1     Completed   0          6m6s
pod/r10k-deploy-1573860600-qhk5j    0/1     Completed   0          4m6s
pod/r10k-deploy-1573860720-hhkpp    0/1     Completed   0          2m6s
pod/r10k-deploy-1573860840-tsx2n    0/1     Completed   0          6s

NAME               TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)             AGE
service/postgres   ClusterIP   10.0.193.66   <none>        5432/TCP            31m
service/puppet     ClusterIP   10.0.79.57    <none>        8140/TCP            31m
service/puppetdb   ClusterIP   10.0.232.39   <none>        8080/TCP,8081/TCP   31m

NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/postgres       1/1     1            1           31m
deployment.apps/puppetdb       1/1     1            1           31m
deployment.apps/puppetserver   1/1     1            1           31m

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/postgres-584d75d8b        1         1         1       31m
replicaset.apps/puppetdb-5f6fd6df7d       1         1         1       31m
replicaset.apps/puppetserver-54f889b9c5   1         1         1       31m

NAME                               COMPLETIONS   DURATION   AGE
job.batch/r10k-deploy-1573860480   1/1           3s         6m6s
job.batch/r10k-deploy-1573860600   1/1           3s         4m6s
job.batch/r10k-deploy-1573860720   1/1           3s         2m6s
job.batch/r10k-deploy-1573860840   1/1           3s         6s

NAME                        SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/r10k-deploy   */2 * * * *   False     1        14s             31m
```

## Configuration

The following table lists the configurable parameters of the Puppetserver chart and their default values.

Parameter | Description | Default
--------- | ----------- | -------
`puppetserver.name` | puppetserver component label | `puppetserver`
`puppetserver.image` | puppetserver image | `puppet/puppetserver`
`puppetserver.tag` | puppetserver img tag | `6.7.1`
`puppetserver.resources` | puppetserver resource limits | ``
`puppetserver.extraEnv` | puppetserver additional container env vars |``
`puppetserver.pullPolicy` | puppetserver img pull policy | `IfNotPresent`
`puppetserver.fqdns.alternateServerNames` | puppetserver alternate fqdns |``
`puppetserver.service.type` | puppetserver svc type | `ClusterIP`
`puppetserver.service.port` | puppetserver svc port | `8140`
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
`r10k.cronJob.schedule` | r10k cron job schedule policy | `*/2 * * * *`
`r10k.resources` | r10k resource limits |``
`r10k.extraArgs` | r10k additional container env args |``
`r10k.extraEnv` | r10k additional container env vars |``
`r10k.viaHttps.repo`| r10k https repo selector |``
`r10k.viaHttps.credentials.username`| r10k https username |``
`r10k.viaHttps.credentials.password`| r10k https password |``
`r10k.viaHttps.credentials.existingSecret`| r10k https secret that holds https username and password |``
`r10k.viaSsh.repo`| r10k ssh repo selector |``
`r10k.viaSsh.credentials.ssh.value`| r10k ssh key file |``
`r10k.viaSsh.credentials.known_hosts.value`| r10k ssh known hosts file |``
`r10k.viaSsh.credentials.existingSecret`| r10k ssh secret that holds ssh key and known hosts files |``
`postgres.name` | postgres component label | `postgres`
`postgres.image` | postgres img | `postgres`
`postgres.tag` | postgres img tag | `9.6.15`
`postgres.pullPolicy` | postgres img pull policy | `IfNotPresent`
`postgres.resources` | postgres resource limits |``
`postgres.extraEnv` | postgres additional container env vars |``
`puppetdb.name` | puppetdb component label | `puppetdb`
`puppetdb.image` | puppetdb img | `puppet/puppetdb`
`puppetdb.tag` | puppetdb img tag | `6.7.3`
`puppetdb.pullPolicy` | puppetdb img pull policy | `IfNotPresent`
`puppetdb.resources` | puppetdb resource limits |``
`puppetdb.extraEnv` | puppetdb additional container env vars |``
`puppetdb.credentials.username`| puppetdb username |`puppetdb`
`puppetdb.credentials.value.password`| puppetdb password |`20-char randomly generated`
`puppetdb.credentials.password.existingSecret`| k8s secret that holds puppetdb password |``
`puppetdb.credentials.password.existingSecretKey`| k8s secret key that holds puppetdb password |``
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

## Chart's Dev Team

* Lead Developer: Miroslav Hadzhiev (miroslav.hadzhiev@gmail.com)
* Developer: Scott Cressi (scottcressi@gmail.com)
* Developer: Morgan Rhodes (morgan@puppet.com)
