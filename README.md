
# pupperware

Run a container-based deployment of Puppet Infrastructure.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

Running Puppet Infrastructure in [Kubernetes](https://kubernetes.io/) is also a very viable option. To get started with that, you will need a running K8s cluster with [Helm](https://helm.sh/) deployed.

We've been developing our own Helm chart which can get you up & running fast. You can find it [here](k8s). We have a plan to start hosting it soon as a Helm chart and publish it in the fantastic [Helm Hub](https://hub.helm.sh/). The latter will allow you to make use of it by just adding the repo in your configured Helm repos.

## Required versions

* Docker Compose - must support `version: '3'` of the compose file format, which requires Docker Engine `1.13.0+`. [Full compatibility matrix](https://docs.docker.com/compose/compose-file/compose-versioning/)
  * Linux is tested with docker-compose `1.22`
  * Windows is tested with `docker-compose version 1.26.0-rc3, build 46118bc5`
  * OSX is tested with `docker-compose version 1.23.2, build 1110ad01`
* Docker Engine support is only tested on versions newer than `17.09.0-ce`
  * Linux is tested with (client and server) `17.09.0-ce` using API version `1.32` (`Git commit:   afdb6d4`)
  * Windows is tested with Docker Desktop Edge 2.2.3.0 on Windows 10 2004 with WSL2 and Ubuntu 18.04
      - Client `19.03.8` using API version `1.40` (`Git commit:        afacb8b`)
      - Server `19.03.8` using API version `1.40 (minimum version 1.12)` (`Git commit:        afacb8b`) with `Experimental: true`
  * OSX is tested during development with `Docker Engine - Community` edition
      - Client `18.09.1` using API version `1.39` (`Git commit:        4c52b90`)
      - Server `18.09.1` using API version `1.39 (minimum version 1.12)` (`Git commit:       4c52b90`)

## Provisioning

Once you have Docker Compose installed, you can start the stack on Linux or OSX with:
```
    DNS_ALT_NAMES=host.example.com docker-compose up -d
```

The value of `DNS_ALT_NAMES` must list all the names, as a comma-separated
list, under which the Puppet server in the stack can be reached from
agents. It will have `puppet` prepended to it as that
name is used by PuppetDB to communicate with the Puppet server. The value of
`DNS_ALT_NAMES` only has an effect the first time you start the stack, as it
is placed into the server's SSL certificate. If you need to change it after
that, you will need to properly revoke the server's certificate and restart
the stack with the changed `DNS_ALT_NAMES` value.

When you first start the Puppet Infrastructure, the stack will create a number of Docker volumes to store the persistent data that should survive the restart of your infrastructure. The actual location on disk of these volumes may be examined with the `docker inspect` command. The following volumes include:

* `puppetserver-code`: the Puppet code directory.
* `puppetserver-config`: Puppet configuration files, including `puppet/ssl/` containing certificates for your infrastructure. This volume is populated with default configuration files if they are not present when the stack starts
up.
* `puppetdb-ssl`: certificates in use by the PuppetDB instance in the
  stack.
* `puppetdb-postgres`: the data files for the PostgreSQL instance used by
PuppetDB
* `puppetserver-data`: persistent data for Puppet Server

## Container Versions

By default, the puppetserver and puppetdb containers will use the `latest` tag.
`PUPPETSERVER_VERSION` and `PUPPETDB_VERSION` environment variables have been
added to the compose file so you can pin versions if you need to by setting those
on the command line, or in a `.env` file.

## Pupperware on Windows (using WSL2)

Complete instructions for provisiong a server with WSL2 support are in [README-windows.md](./README-windows.md)

Creating the stack from PowerShell is nearly identical to other platforms, aside from how environment variables are declared:

``` powershell
PS> $ENV:DNS_ALT_NAMES = 'host.example.com'

PS> docker-compose up
Creating network "pupperware_default" with the default driver
Creating volume "pupperware_puppetserver-code" with default driver
Creating volume "pupperware_puppetserver-config" with default driver
Creating volume "pupperware_puppetserver-data" with default driver
Creating volume "pupperware_puppetdb-ssl" with default driver
Creating volume "pupperware_puppetdb-postgres" with default driver
Creating pupperware_postgres_1 ...

Creating pupperware_puppet_1   ...

Creating pupperware_puppet_1   ... done

Creating pupperware_postgres_1 ... done

Creating pupperware_puppetdb_1 ...

Creating pupperware_puppetdb_1 ... done

...
```

To delete the stack:

``` powershell
PS> docker-compose down
Removing network pupperware_default
...
```

## Managing the stack

The script `bin/puppet` (or `bin\puppet.ps1` on Windows) makes it easy to run `puppet` commands on the
puppet master. For example, `./bin/puppet config print autosign --section
master` prints the current setting for autosigning, which is `true` by
default. In a similar manner, any other task that you would perform on a
puppet master by running `puppet x y z ...` can be achieved against the
stack by running `./bin/puppet x y z ...`.

There is also a similar script providing easy access to `puppetserver` commands. This is particularly
useful for CA and cert management via the `ca` subcommand.

### Changing postgresql password

The postgresql instance uses password authentication for communication with the
puppetdb instance. If you need to change the postgresql password, you'll need to
do the following:
* update the password in postgresql: `docker-compose exec postgres /bin/bash -c "psql -U \$POSTGRES_USER -c \"ALTER USER \$POSTGRES_USER PASSWORD '$dbpassword'\";"`
* update values for `PUPPETDB_PASSWORD` and `POSTGRES_PASSWORD` in docker-compose.yml
* rebuild and restart containers affected by these changes: `docker-compose up --detach --build`

## Running tests

### Running tests locally
This repo contains some simple tests that can be run with [RSpec](http://rspec.info).
To run these tests you need to have Ruby, Docker, and Docker Compose installed on the
machine where you're running the tests. The tests depend on the 'rspec' and 'json'
rubygems. The tests are known to run on at least ruby 1.9.3-p551 and as new as
ruby 2.4.3p205.

**NOTE** These tests will start and stop the cluster
running from the current checkout of Pupperware, so be careful where you run them
from.

To run the tests:
1. `bundle install --with test`
2. `bundle exec rspec spec`

## Containers

The containers used in pupperware are generated based on dockerfiles in the
repos for [puppetserver](https://github.com/puppetlabs/puppetserver/tree/master/docker)
and [puppetdb](https://github.com/puppetlabs/puppetdb/tree/master/docker).
Published containers can be found on [dockerhub](https://hub.docker.com/u/puppet).

## Analytics Data Collection

The Puppet owned containers run in the pupperware stack collect usage data. You can opt out of providing this data.

### What data is collected?
* Version of the puppetserver container.
* Version of the puppetdb container.
* Anonymized IP address is used by Google Analytics for Geolocation data, but the IP address is not collected.

### Why does pupperware collect data?

We collect data to help us understand how the containers are used and make decisions about upcoming changes.

### How can I opt out of pupperware container data collection?

Create a `.env` file in this directory with the contents:

```
PUPPERWARE_ANALYTICS_ENABLED=false
```

This file is in the `.gitignore` file and will not be managed or changed by pupperware.

## License

See [LICENSE](LICENSE) file.

## Issue Tracking

Please report any issues as GitHub issues in this repo.

## Contact us!

If you have questions or comments about pupperware, feel free to send a message
to the [puppet-users mailing list](https://groups.google.com/forum/#!forum/puppet-users)
or reach out in the #puppet channel in the [puppet community slack](https://slack.puppet.com/).
