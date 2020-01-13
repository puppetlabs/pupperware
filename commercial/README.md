# pupperware-commercial

Run a container-based deployment of Puppet Enterprise.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [pupperware-commercial](#pupperware-commercial)
  + [Running](#running)
  + [Tests](#tests)
  + [Local Configuration](#local-configuration)
  + [Code Manager Setup](#code-manager-setup)
  + [Verifying status](#verifying-status)
- [Additional Customization](#further-customization)
  + [puppet](#puppet)
  + [pe-orchestration-services](#pe-orchestration-services)
  + [pe-console-services](#pe-console-services)
  + [pe-bolt-server](#pe-bolt-server)
  + [puppetdb](#puppetdb)
  + [postgres](#postgres)
- [Additional Information](#additional-information)

<!-- markdown-toc end -->

## Running

1. Run `docker-compose up` (or `make up`)
2. Go to https://localhost in your browser (or `make console`)
3. Login with `admin/pupperware`

To see things working, try doing a puppet-code deploy:
```shell
docker run --rm --network pupperware-commercial \
  -e RBAC_USERNAME=admin -e RBAC_PASSWORD=pupperware \
  -e PUPPETSERVER_HOSTNAME=puppet.test \
  -e PUPPETDB_HOSTNAME=puppetdb.test \
  -e PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services.test \
  -e PE_ORCHESTRATION_SERVICES_HOSTNAME=pe-orchestration-services.test \
  artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:kearney-latest \
  puppet-code deploy --dry-run
```

Or if you're using the Makefile:
```shell
make client
puppet-code deploy --dry-run
```

## Tests

Make sure the stack isn't already running, then: `make test`

## Default Stack Configuration

The `docker-compose.yml` contains a nominally configured Puppet Enterprise stack that uses the `.test` DNS TLD (top-level domain) inside the Docker container network and overrides many of the default environment variables for containers. It also provisions a customized version of Postgres inside of a container, rather than using an external Postgres instance.

## Local Configuration

Create a `docker-compose.override.yml` file to add or override the default
docker-compose configuration. This file is git ignored for convenience.

Docker volumes may be bind mounted inside the directory named `volumes/` at the root of this repository, which is also git ignored.

## Code Manager Setup

To specify a control repo, define the `R10K_REMOTE` environment variable on the
`puppet` service in the `docker-compose.yml`. Both public (via HTTPS) and private (via SSH) git repositories are supported.

If the control repo is private, the `R10K_REMOTE` URL should use the SSH protocol like `git@github.com:user/repo.git`. In addition, an SSH key named `id-control_repo.rsa` must be generated and
supplied to the `puppet` service via a [Docker bind mount](https://docs.docker.com/storage/bind-mounts/) at
`/etc/puppetlabs/puppetserver/ssh` (see the commented example in the `docker-compose.yml`). The public key needs to be added to the git
servers control repo configuration. Additional SSH configuration files `config`, `authorited_keys` and `known_hosts`, will be used if they are present in the bind mount.

## Verifying status

All containers have implemented healthchecks, which indicate that all services within the container are running correctly when the container reports `healthy`. Puppet Enterprise is fully operational when all healthchecks reported from `docker-compose ps` are `healthy`, like:

```
                      Name                                     Command                  State                                                   Ports
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pupperware-commercial_pe-bolt-server_1              /tini -g -- /docker-entryp ...   Up (healthy)   62658/tcp, 62659/tcp
pupperware-commercial_pe-console-services_1         /tini -g -- /docker-entryp ...   Up (healthy)   0.0.0.0:4430->4430/tcp, 0.0.0.0:443->4431/tcp, 0.0.0.0:4432->4432/tcp, 0.0.0.0:4433->4433/tcp
pupperware-commercial_pe-orchestration-services_1   /tini -g -- /docker-entryp ...   Up (healthy)   8140/tcp, 0.0.0.0:8142->8142/tcp, 0.0.0.0:8143->8143/tcp
pupperware-commercial_postgres_1                    docker-entrypoint.sh postg ...   Up (healthy)   5432/tcp
pupperware-commercial_puppet_1                      /tini -g -- /docker-entryp ...   Up (healthy)   0.0.0.0:8140->8140/tcp, 0.0.0.0:8170->8170/tcp
pupperware-commercial_puppetdb_1                    /tini -g -- /docker-entryp ...   Up (healthy)   0.0.0.0:32769->8080/tcp, 0.0.0.0:32768->8081/tcp
```

# Additional Customization

## Service-specific Docker configuration via environment variables

Configuration of Puppet Enterprise in containers is much different than a typical PE install. Some configuration **must** be set before the containers are started, by specifying environment variables in the compose stacks yaml. Most configuration files within containers are not intended to be user modified, and are controlled through the setting of these environment variables only. Configuration files derived from environment variable configuration are written to each containers persistent volume to support easy version upgrades -- do not modify these files directly as container restarts may overwrite them.

The following values, many of which are already overriden in the `docker-compose.yml` are designed to be user configurable. Default values are listed for reference. In many cases, different services must agree on values - for instance `PUPPETSERVER_HOSTNAME` should generally be the same value across all services.

### puppet

| Name                                   | Usage / Default                                                                                                                                                                             |
|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CERTNAME**                           | The DNS name used on the masters SSL certificate<br><br>`pe-puppetserver`                                                                                                                   |
| **DNS_ALT_NAMES**                      | Additional DNS names to add to the masters SSL certificate                                                                                                                                  |
| **PUPPETDB_HOSTNAME**                  | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                                  |
| **PUPPETDB_SSL_PORT**                  | The port for the puppetdb service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`8081`                                                                  |
| **POSTGRES_HOSTNAME**                  | The DNS hostname of the postgres service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`postgres`                                                       |
| **PE_CONSOLE_SERVICES_HOSTNAME**       | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                            |
| **PE_ORCHESTRATION_SERVICES_HOSTNAME** | The DNS hostname of the pe-orchestration-services service<br><br>`pe-orchestration-services`                                                                                                |
| **PE_ORCHESTRATION_SERVICES_PORT**     | The port for the pe-orchestration-services service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`8143`                                                 |
| **R10K_REMOTE**                        | For public repos, set the control repo URL like https://github.com/puppetlabs/control-repo.git.<br>For private repos, use git@github.com:user/repo.git and provide SSH keys in a bind mount |
| **PUPPETSERVER_JAVA_ARGS**             | Arguments passed directly to the JVM when starting the service<br><br>`-Xms768m -Xmx768m`                                                                                                   |

### pe-orchestration-services

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`pe-orchestration-services`                                                                                              |
| **DNS_ALT_NAMES**                       | Additional DNS names to add to the services SSL certificate (Dockers `hostname` and FQDN are already included)<br><br>`${HOSTNAME},$(hostname -s),$(hostname -f),${DNS_ALT_NAMES}` |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETDB_HOSTNAME**                   | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                         |
| **POSTGRES_HOSTNAME**                   | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **PE_BOLT_SERVER_HOSTNAME**             | The DNS hostname of the pe-bolt-server service<br><br>`pe-bolt-server`                                                                                                             |
| **PE_CONSOLE_SERVICES_HOSTNAME**        | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                   |
| **PUPPERWARE_ADMIN_PASSWORD**           | Log into the PE console using the username `admin` and this password value, once all containers are healthy<br><br>`pupperware`                                                    |
| **PE_ORCHESTRATION_SERVICES_LOG_LEVEL** | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **PE_ORCHESTRATION_SERVICES_JAVA_ARGS** | Arguments passed directly to the JVM when starting the service<br><br>`-Xmx1g`                                                                                                     |


### pe-console-services

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`pe-console-services`                                                                                                    |
| **DNS_ALT_NAMES**                       | Additional DNS names to add to the services SSL certificate (Dockers `hostname` and FQDN are already included)<br><br>`${HOSTNAME},$(hostname -s),$(hostname -f),${DNS_ALT_NAMES}` |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETSERVER_CERTNAME**               | The primary DNS name on the puppet master certificate<br><br>`pe-puppetserver`                                                                                                     |
| **PUPPETSERVER_PORT**                   | The listening port of the puppet master<br><br>`8140`                                                                                                                              |
| **PUPPETDB_HOSTNAME**                   | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                         |
| **PUPPETDB_CERTNAME**                   | The primary DNS name on the puppetdb certificate<br><br>`pe-puppetdb`                                                                                                              |
| **PUPPETDB_SSL_PORT**                   | The listening port for puppetdb<br><br>`8081`                                                                                                                                      |
| **POSTGRES_HOSTNAME**                   | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **POSTGRES_PORT**                       | The listening port for postgres<br><br>`5432`                                                                                                                                      |
| **PE_ORCHESTRATION_SERVICES_HOSTNAME**  | The DNS hostname of the pe-orchestration-services service<br><br>`pe-orchestration-services`                                                                                       |
| **PE_ORCHESTRATION_SERVICES_CERTNAME**  | The primary DNS name on the pe-orchestration-services certificate<br><br>`pe-orchestration-services`                                                                               |
| **PE_CONSOLE_SERVICES_LOG_LEVEL**       | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **PE_CONSOLE_SERVICES_JAVA_ARGS**       | Arguments passed directly to the JVM when starting the service<br><br>`-Xmx192m`                                                                                                   |

### pe-bolt-server

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`pe-bolt-server`                                                                                                         |
| **DNS_ALT_NAMES**                       | Additional DNS names to add to the services SSL certificate (Dockers `hostname` and FQDN are already included)<br><br>`${HOSTNAME},$(hostname -s),$(hostname -f),${DNS_ALT_NAMES}` |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PE_BOLT_SERVER_LOGLEVEL**             | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **WHITELIST_HOSTNAME.0**                | The DNS hostnamesof all services allowed to connect to this service<br><br>`pe-orchestration-services`                                                                             |
| **WHITELIST_HOSTNAME.1**                | Additional services may be added as **WHITELIST_HOSTNAME.#** starting with `2` for `#`, etc<br><br>`pe-bolt-server`                                                                |

### puppetdb

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`pe-puppetdb`                                                                                                            |
| **DNS_ALT_NAMES**                       | Additional DNS names to add to the services SSL certificate (Dockers `hostname` and FQDN are already included)<br><br>`${HOSTNAME},$(hostname -s),$(hostname -f),${DNS_ALT_NAMES}` |
| **USE_PUPPETSERVER**                    | Should always be set to `true`<br><br>`true`                                                                                                                                       |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETDB_POSTGRES_HOSTNAME**          | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **PUPPETDB_POSTGRES_PORT**              | The listening port for postgres<br><br>`5432`                                                                                                                                      |
| **PUPPETDB_POSTGRES_DATABASE**          | The name of the puppetdb database in postgres<br><br>`puppetdb`                                                                                                                    |
| **PUPPETDB_USER**                       | The puppetdb database user<br><br>`puppetdb`                                                                                                                                       |
| **PUPPETDB_PASSWORD**                   | The puppetdb database password<br><br>`puppetdb`                                                                                                                                   |
| **PUPPETDB_NODE_TTL**                   | Mark as ‘expired’ nodes that haven’t seen any activity (no new catalogs, facts, or reports) in the specified amount of time<br><br>`7d`                                            |
| **PUPPETDB_NODE_PURGE_TTL**             | Automatically delete nodes that have been deactivated or expired for the specified amount of time<br><br>`14d`                                                                     |
| **PUPPETDB_REPORT_TTL**                 | Automatically delete reports that are older than the specified amount of time<br><br>`14d`                                                                                         |
| **PE_CONSOLE_SERVICES_HOSTNAME**        | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                   |
| **PUPPETDB_JAVA_ARGS**                  | Arguments passed directly to the JVM when starting the service<br><br>`-Xms256m -Xmx256m -XX:+PrintGCDetails -XX:+PrintGCDateStamps-Xloggc:/opt/puppetlabs/server/data/puppetdb/logs/puppetdb_gc.log-XX:+UseGCLogFileRotation-XX:NumberOfGCLogFiles=16 -XX:GCLogFileSize=64m` |

### postgres

| Name                                    | Usage / Default                                                                                        |
|-----------------------------------------|--------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`postgres`                                   |
| **PGPORT**                              | The listening port for postgres<br><br>`5432`
| **POSTGRES_DB**                         | The name of the puppetdb database in postgres<br><br>`puppetdb`                                        |
| **POSTGRES_USER**                       | The puppetdb database user<br><br>`puppetdb`                                                           |
| **POSTGRES_PASSWORD**                   | The puppetdb database password<br><br>`puppetdb`                                                       |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                  |
| **PUPPETDB_CERTNAME**                   | The primary DNS name on the puppetdb certificate<br><br>`pe-puppetdb`                                  |
| **PE_CONSOLE_SERVICES_CERTNAME**        | The primary DNS name of the pe-console-services certificate<br><br>`pe-console-services`               |
| **PE_ORCHESTRATION_SERVICES_CERTNAME**  | The primary DNS name on the pe-orchestration-services certificate<br><br>`pe-orchestration-services`   |

# Additional Information

See https://github.com/puppetlabs/pupperware for more information.
