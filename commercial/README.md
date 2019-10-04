# pupperware-commercial

Run a container-based deployment of Puppet Enterprise.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

### Running

1. Run `docker-compose up` (or `make up`)
2. Go to https://localhost in your browser
3. Login with `admin/pupperware`

To see things working, try doing a puppet-job run against the agent node:
```shell
docker run --rm --network pupperware-commercial \
  -e RBAC_USERNAME=admin -e RBAC_PASSWORD=pupperware \
  -e PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services.test \
  artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:kearney-latest \
  puppet-job run --nodes puppet-agent.test --service-url https://pe-orchestration-services.test:8143/
```

### Tests

Make sure the stack isn't already running, then: `make test`

----

# pupperware

Run a container-based deployment of Puppet Infrastructure.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

## Required versions

* Docker Compose - must support `version: '3'` of the compose file format, which requires Docker Engine `1.13.0+`. [Full compatibility matrix](https://docs.docker.com/compose/compose-file/compose-versioning/)
  * Linux is tested with docker-compose `1.22`
  * Windows is tested with `docker-compose version 1.24.0-rc1, build 0f3d4dda`
  * OSX is tested with `docker-compose version 1.23.2, build 1110ad01`
* Docker Engine support is only tested on versions newer than `17.09.0-ce`
  * Linux is tested with (client and server) `17.09.0-ce` using API version `1.32` (`Git commit:   afdb6d4`)
  * Windows is tested with newer nightly versions that enable LCOW support / fix bugs in the Docker runtime (minimum required is edge release `18.02`, but latest highly recommended)
      - Client `master-dockerproject-2019-01-08` using API version `1.40` (`Git commit:        d04b6165`)
      - Server `master-dockerproject-2019-01-08` using API version `1.40 (minimum version 1.24)` (`Git commit:        77df18c`) with `Experimental: true`
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
agents. It will have `puppet` and `puppet.internal` prepended to it as that
name is used by PuppetDB to communicate with the Puppet server. The value of
`DNS_ALT_NAMES` only has an effect the first time you start the stack, as it
is placed into the server's SSL certificate. If you need to change it after
that, you will need to properly revoke the server's certificate and restart
the stack with the changed `DNS_ALT_NAMES` value.

Optionally, you may also provide a desired `DOMAIN` value, other than default
value of `internal` to further define how the service hosts are named. It is
not necessary to change `DNS_ALT_NAMES` as the default value already takes into
account any custom domain.

```
    DOMAIN=foo docker-compose up -d
```

When you first start the Puppet Infrastructure, the stack will create a number of Docker volumes to store the persistent data that should survive the restart of your infrastructure. The actual location on disk of these volumes may be examined with the `docker inspect` command. The following volumes include:

* `puppetserver`: persistent data for Puppet Server including generated certs, logs, reports and the file bucket
* `puppetserver-packages`: packages for the simplified installer
* `code-manager`: code manager data, filesync data, staging and master code dir from the Puppet Server
* `code-manager-ssh-key`: will be created if an existing bind mount path to `id-control_repo.rsa` is not specified in `docker-compose.yml` so that a file may be copied in later to the naemd volume
* `orchestration-services`: data files for orchestration services, including generated certificates and logs
* `console-services`: data files for console services, including generated certificates and logs
* `bolt-server`: data files for bolt server, including generated certificates and logs
* `puppetdb`: data files for puppetdb, including generated certificates and logs
* `puppetdb-postgres`: the data files for the PostgreSQL instance used by
PuppetDB (the standard Postgres `PGDATA` volume)


## Pupperware on Windows (using LCOW)

Complete instructions for provisiong a server with LCOW support are in [README-windows.md](./README-windows.md)

Creating the stack from PowerShell is nearly identical to other platforms, aside from how environment variables are declared:

``` powershell
PS> $ENV:DNS_ALT_NAMES = 'host.example.com'

PS> docker-compose up
Creating network "pupperware-commercial" with the default driver
Creating volume "pupperware-commercial_puppetserver" with default driver
Creating volume "pupperware-commercial_puppetserver-packages" with default driver
Creating volume "pupperware-commercial_code-manager" with default driver
Creating volume "pupperware-commercial_orchestration-services" with default driver
Creating volume "pupperware-commercial_console-services" with default driver
Creating volume "pupperware-commercial_bolt-server" with default driver
Creating volume "pupperware-commercial_puppetdb" with default driver
Creating volume "pupperware-commercial_puppetdb-postgres" with default driver
Creating pupperware-commercial_puppet-agent_1 ...
Creating pupperware-commercial_puppet_1       ...
Creating pupperware-commercial_test-sshd_1    ...
Creating pupperware-commercial_pe-bolt-server_1 ...
Creating pupperware-commercial_postgres_1       ...
Creating pupperware-commercial_postgres_1       ... done
Creating pupperware-commercial_pe-bolt-server_1 ... done
Creating pupperware-commercial_test-sshd_1      ... done
Creating pupperware-commercial_puppet-agent_1   ... done
Creating pupperware-commercial_puppet_1         ... done
Creating pupperware-commercial_pe-console-services_1 ...
Creating pupperware-commercial_puppetdb_1            ...
Creating pupperware-commercial_pe-orchestration-services_1 ...
Creating pupperware-commercial_puppetdb_1                  ... done
Creating pupperware-commercial_pe-orchestration-services_1 ... done
Creating pupperware-commercial_pe-console-services_1       ... done

...
```

To delete the stack:

``` powershell
PS> docker-compose down
Removing network pupperware-commercial_default
...
```

Note that `docker-compose down` may perform slowly on Windows - see [docker/for-win 629](https://github.com/docker/for-win/issues/629) and [docker/compose](https://github.com/docker/compose/issues/3419) for further information.

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
