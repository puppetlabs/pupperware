# pupperware-commercial

Run a container-based deployment of Puppet Enterprise.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

### Running

1. Run `docker-compose up` (or `make up`)
2. Go to https://localhost in your browser
3. Login with `admin/admin`

To see things working, try doing a puppet-job run against the agent node:
```shell
docker run --rm --network pupperware-commercial \
  -e RBAC_USERNAME=admin -e RBAC_PASSWORD=admin \
  -e PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services.test \
  artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:19.1.3 \
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

Once you have Docker Compose installed, you can start the stack on Linux or macOS with:
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

When you first start the Puppet Infrastructure, the stack will create a
`volumes/` directory with a number of sub-directories to store the
persistent data that should survive the restart of your infrastructure. This
directory is created right next to the Docker Compose file and contains the
following sub-directories:

* `code/`: the Puppet code directory.
* `puppet/`: Puppet configuration files, including `puppet/ssl/` containing
certificates for your infrastructure. This directory is populated with
default configuration files if they are not present when the stack starts
up. You can make configuration changes to your stack by editing files in
this directory and restarting the stack.
* `puppetdb/ssl/`: certificates in use by the PuppetDB instance in the
  stack.
* `puppetdb-postgres/`: the data files for the PostgreSQL instance used by
PuppetDB
* `serverdata/`: persistent data for Puppet Server
* Note: On OSX, you must add the `volumes` directory to "File Sharing" under
  `Preferences>File Sharing` in order for these directories to be created
  and volume-mounted automatically. There is no need to add each sub directory.

## Pupperware on Windows (using LCOW)

Complete instructions for provisiong a server with LCOW support are in [README-windows.md](./README-windows.md)

Due to [permissions issues with Postgres](https://forums.docker.com/t/trying-to-get-postgres-to-work-on-persistent-windows-mount-two-issues/12456/4) on Docker for Windows, to run under the LCOW environment, the Windows stack relies on the [`stellirin/postgres-windows`](https://hub.docker.com/r/stellirin/postgres-windows/) Windows variant of the upstream [`postgres`](https://hub.docker.com/_/postgres/) container instead.

To create the stack:

``` powershell
PS> $ENV:DNS_ALT_NAMES = 'host.example.com'

PS> docker-compose -f .\docker-compose.yml -f .\docker-compose.windows.yml up
Creating network "pupperware_default" with the default driver
Creating pupperware_puppet_1_4be38bcee346   ... done
Creating pupperware_postgres_1_c82bfeb597f5 ... done
Creating pupperware_puppetdb_1_bcd7e5f54a3f ... done
Attaching to pupperware_postgres_1_cf9a935a098e, pupperware_puppet_1_79b6ff064b91, pupperware_puppetdb_1_70edf5d8cd1e

...
```

To delete the stack:

``` powershell
PS> docker-compose down
Removing network pupperware_default
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
