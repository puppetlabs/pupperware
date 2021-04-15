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
  + [Service-specific Docker configuration via environment variables](#Service-specific-docker-configuration-via-environment-variables)
    * [puppet](#puppet)
    * [pe-orchestration-services](#pe-orchestration-services)
    * [pe-console-services](#pe-console-services)
    * [pe-bolt-server](#pe-bolt-server)
    * [puppetdb](#puppetdb)
    * [postgres](#postgres)
  + [External PostgreSQL](#external-postgresql)
  + [External CA Support](#external-ca-support)
- [Additional Information](#additional-information)

<!-- markdown-toc end -->

## Running

1. Run `make up`
2. Go to https://localhost in your browser (or `make console`)
3. Login with `admin/admin`

To see things working, try doing a puppet-code deploy:
```shell
docker run --rm --network pupperware-commercial \
  -e RBAC_USERNAME=admin -e RBAC_PASSWORD=admin \
  -e PUPPETSERVER_HOSTNAME=puppet \
  -e PUPPETDB_HOSTNAME=puppetdb \
  -e PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services \
  -e PE_ORCHESTRATION_SERVICES_HOSTNAME=pe-orchestration-services \
  artifactory.delivery.puppetlabs.net/platform-services-297419/pe-and-platform/pe-client-tools:latest \
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

The `docker-compose.yml` contains a nominally configured Puppet Enterprise stack that overrides many of the default environment variables for containers. It also provisions a customized version of Postgres inside of a container, rather than using an external Postgres instance.

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
| **PUPPETSERVER_PORT**                  | The listening port of the puppet master<br><br>`8140`                                                                                                                                       |
| **PUPPETSERVER_LOG_LEVEL**             | The logging level to use for this service<br><br>`info`                                                                                                                                     |
| **PUPPETDB_HOSTNAME**                  | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                                  |
| **PUPPETDB_SSL_PORT**                  | The SSL port for the puppetdb service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`8081`                                                              |
| **POSTGRES_HOSTNAME**                  | The DNS hostname of the postgres service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`postgres`                                                       |
| **PE_CONSOLE_SERVICES_HOSTNAME**       | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                            |
| **PE_ORCHESTRATION_SERVICES_HOSTNAME** | The DNS hostname of the pe-orchestration-services service<br><br>`pe-orchestration-services`                                                                                                |
| **PE_ORCHESTRATION_SERVICES_PORT**     | The port for the pe-orchestration-services service<br>Also written to Hiera data to be consumed by `puppet::enterprise` class<br><br>`8143`                                                 |
| **R10K_REMOTE**                        | For public repos, set the control repo URL like https://github.com/puppetlabs/control-repo.git.<br>For private repos, use git@github.com:user/repo.git and provide SSH keys in a bind mount |
| **PUPPETSERVER_JAVA_ARGS**             | Arguments passed directly to the JVM when starting the service<br><br>`-Xms768m -Xmx768m`                                                                                                   |

### pe-orchestration-services

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **PCP_BROKER_PORT**                     | The listening port for the pcp-broker service<br><br>`8142`                                                                                                                        |
| **PE_ORCHESTRATION_SERVICES_PORT**      | The listening port for the pe-orchestration-services service<br><br>`8143`                                                                                                         |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETSERVER_PORT**                   | The port of the puppet master<br><br>`8140`                                                                                                                                        |
| **PUPPETDB_HOSTNAME**                   | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                         |
| **PUPPETDB_SSL_PORT**                   | The SSL port of the puppetdb<br><br>`8081`                                                                                                                                         |
| **POSTGRES_HOSTNAME**                   | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **POSTGRES_PORT**                       | The port for postgres<br><br>`5432`                                                                                                                                                |
| **PE_BOLT_SERVER_HOSTNAME**             | The DNS hostname of the pe-bolt-server service<br><br>`pe-bolt-server`                                                                                                             |
| **PE_ACE_SERVER_HOSTNAME**              | The DNS hostname of the ace-server service<br><br>`ace`                                                                                                                            |
| **PE_CONSOLE_SERVICES_HOSTNAME**        | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                   |
| **ADMIN_RBAC_PASSWORD**                 | Log into the PE console using the username `admin` and this password value, once all containers are healthy<br><br>`admin`                                                         |
| **PE_ORCHESTRATION_SERVICES_LOG_LEVEL** | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **PE_ORCHESTRATION_SERVICES_JAVA_ARGS** | Arguments passed directly to the JVM when starting the service<br><br>`-Xmx1g`                                                                                                     |

### pe-console-services

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETSERVER_PORT**                   | The port of the puppet master<br><br>`8140`                                                                                                                                        |
| **PUPPETDB_HOSTNAME**                   | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                         |
| **PUPPETDB_SSL_PORT**                   | The SSL port for puppetdb<br><br>`8081`                                                                                                                                            |
| **POSTGRES_HOSTNAME**                   | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **POSTGRES_PORT**                       | The port for postgres<br><br>`5432`                                                                                                                                                |
| **PE_ORCHESTRATION_SERVICES_HOSTNAME**  | The DNS hostname of the pe-orchestration-services service<br><br>`pe-orchestration-services`                                                                                       |
| **PE_ORCHESTRATION_SERVICES_PORT**      | The port for the pe-orchestration-services service<br><br>`8143`                                                                                                                   |
| **RBAC_CERTIFICATE_ALLOWLIST**          | The primary DNS cert names for all services allowed to contact RBAC<br><br>`pe-puppetserver,pe-puppetdb,pe-orchestration-services`                                                 |
| **PE_CONSOLE_SERVICES_LOG_LEVEL**       | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **PE_CONSOLE_SERVICES_JAVA_ARGS**       | Arguments passed directly to the JVM when starting the service<br><br>`-Xmx192m`                                                                                                   |

### pe-bolt-server

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETSERVER_PORT**                   | The port of the puppet master<br><br>`8140`                                                                                                                                        |
| **PE_BOLT_SERVER_LOGLEVEL**             | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **WHITELIST_HOSTNAME.0**                | The DNS hostnamesof all services allowed to connect to this service<br><br>`pe-orchestration-services`                                                                             |
| **WHITELIST_HOSTNAME.1**                | Additional services may be added as **WHITELIST_HOSTNAME.#** starting with `2` for `#`, etc<br><br>`pe-bolt-server`                                                                |

### puppetdb

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **PUPPETDB_SSL_PORT**                   | The listening SSL port for puppetdb<br><br>`8081`                                                                                                                                  |
| **PUPPETDB_LOGLEVEL**                   | The logging level to use for this service<br><br>`info`                                                                                                                            |
| **PUPPETDB_POSTGRES_HOSTNAME**          | The DNS hostname of the postgres service<br><br>`postgres`                                                                                                                         |
| **PUPPETDB_POSTGRES_PORT**              | The port for postgres<br><br>`5432`                                                                                                                                                |
| **PUPPETDB_POSTGRES_DATABASE**          | The name of the puppetdb database in postgres<br><br>`puppetdb`                                                                                                                    |
| **PUPPETDB_USER**                       | The puppetdb database user<br><br>`puppetdb`                                                                                                                                       |
| **PUPPETDB_PASSWORD**                   | The puppetdb database password<br><br>`puppetdb`                                                                                                                                   |
| **PUPPETDB_NODE_TTL**                   | Mark as ‘expired’ nodes that haven’t seen any activity (no new catalogs, facts, or reports) in the specified amount of time<br><br>`7d`                                            |
| **PUPPETDB_NODE_PURGE_TTL**             | Automatically delete nodes that have been deactivated or expired for the specified amount of time<br><br>`14d`                                                                     |
| **PUPPETDB_REPORT_TTL**                 | Automatically delete reports that are older than the specified amount of time<br><br>`14d`                                                                                         |
| **PE_CONSOLE_SERVICES_HOSTNAME**        | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                   |
| **PUPPETDB_JAVA_ARGS**                  | Arguments passed directly to the JVM when starting the service<br><br>`-Xms256m -Xmx256m -XX:+UseParallelGC -Xlog:gc*:file=/opt/puppetlabs/server/data/puppetdb/logs/puppetdb_gc.log::filecount=16,filesize=65536 -Djdk.tls.ephemeralDHKeySize=2048` |

### pe-client-tools

| Name                                    | Usage / Default                                                                                                                                                                    |
|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **RBAC_USERNAME**                       | Required. The PE user of the user that will run pe-client-tools.                                                                                                                   |
| **RBAC_PASSWORD**                       | Required. The password to the PE user's account that will run pe-client-tools.                                                                                                     |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                                                                                              |
| **PUPPETDB_HOSTNAME**                   | The DNS hostname of the puppetdb service<br><br>`puppetdb`                                                                                                                         |
| **PE_CONSOLE_SERVICES_HOSTNAME**        | The DNS hostname of the pe-console-services service<br><br>`pe-console-services`                                                                                                   |
| **PE_ORCHESTRATION_SERVICES_HOSTNAME**  | The DNS hostname of the pe-orchestration-services service<br><br>`pe-orchestration-services`                                                                                       |

### postgres

| Name                                    | Usage / Default                                                                                        |
|-----------------------------------------|--------------------------------------------------------------------------------------------------------|
| **CERTNAME**                            | The DNS name used on this services SSL certificate<br><br>`postgres`                                   |
| **DNS_ALT_NAMES**                       | Additional DNS names to add to the services SSL certificate                                            |
| **WAITFORCERT**                         | Number of seconds to wait for certificate to be signed<br><br>`120`                                    |
| **PGPORT**                              | The listening port for postgres<br><br>`5432`                                                          |
| **POSTGRES_DB**                         | The name of the puppetdb database in postgres<br><br>`puppetdb`                                        |
| **POSTGRES_USER**                       | The puppetdb database user<br><br>`puppetdb`                                                           |
| **POSTGRES_PASSWORD**                   | The puppetdb database password<br><br>`puppetdb`                                                       |
| **PUPPETSERVER_HOSTNAME**               | The DNS hostname of the puppet master<br><br>`puppet`                                                  |
| **PUPPETSERVER_PORT**                   | The port of the puppet master<br><br>`8140`                                                            |
| **ALLOWED_CERT_NAMES**                  | The primary DNS cert names for all clients allowed to contact Postgres<br><br>`pe-puppetdb,pe-console-services,pe-orchestration-services`    |

## External PostgreSQL

An external PostgreSQL database can be used instead of using a containerized version of Postgres. This requires setting the Postgres environment variables on the `puppet`, `pe-orchestration-services`, `pe-console-services` and `puppetdb` services and *removing* the `postgres` service and the `puppetdb-postgres` volume from the `docker-compose.yml` configuration.

The PostgreSQL version should be 9.6 or newer. 

The databases `pe-classifier`, `pe-rbac`, `pe-activity`, `pe-inventory`, and `pe-orchestrator` all must exist. Each database requires the extensions `citext`, `pg_trgm`, `plpsql`, and `pgcrypto`. This may be setup by running the following SQL script:

```
CREATE DATABASE "pe-classifier" OWNER "puppetdb";
CREATE DATABASE "pe-rbac" OWNER "puppetdb";
CREATE DATABASE "pe-activity" OWNER "puppetdb";
CREATE DATABASE "pe-inventory" OWNER "puppetdb";
CREATE DATABASE "pe-orchestrator" OWNER "puppetdb";

\c "pe-rbac"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\c "pe-orchestrator"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\c "pe-inventory"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\c "puppetdb"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\c "pe-classifier"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;

\c "pe-activity"
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS plpgsql;

-- used for the healthcheck SSL check
\c "postgres"
CREATE EXTENSION IF NOT EXISTS sslinfo;
```

### PostgreSQL SSL setup

The PE services connections to PostgreSQL is only supported over SSL. 

#### postgresql.conf

The PostgreSQL node will require the complete certificate authority certificate chain for the external party CA, in PEM format. In the default configuration, these files are stored in the `$PGDATA` directory. The follow settings must be enabled in `$PGDATA/postgresql.conf` to correctly enable SSL:

```
ssl=on
# Certificate for the trusted certificate authority (i.e. Puppet master)
ssl_ca_file=root.crt
# Certificate for Postgres, signed by the CA
ssl_cert_file=server.crt
# Certificate revocation list from the CA
ssl_crl_file=root.crl
# Private key for Postgres certificate
ssl_key_file=server.key
```

#### pg_ident.conf

The `$PGDATA/pg_ident.conf` must map certificate names for `pe-console-services`, `pe-orchestration-services` and `puppetdb` services to the `puppetdb` user properly, like:

```
# MAPNAME  SYSTEM-USERNAME                  PG-USERNAME
usermap    pe-console-services              puppetdb
usermap    pe-orchestration-services        puppetdb
usermap    puppetdb                         puppetdb
```

#### pg_hba.conf

Additionally, `$PGDATA/pg_hba.conf` must be configured with this line to enable the ssl connnections:

```
# TYPE  DATABASE     USER     ADDRESS     METHOD
hostssl all          all      all         cert map=usermap
```

## External CA Support

To use certificates from an external CA rather than using the ones generated by the Puppet master CA requires performing a few operations:

* All the named volumes for the compose stack should be created. This can be done by executing `docker-compose up --no-start`.
* For each of the volumes for a given service, the appropriate certificate files should be copied to the correct location inside the volume using the [`docker cp SRC_PATH CONTAINER:DEST_PATH`](https://docs.docker.com/engine/reference/commandline/cp/) command. The specific path depends on the container.
* Entrypoint scripts will automatically change ownership and set permissions on SSL files when the containers first start.

### Cert File Locations

For the services `puppet`, `pe-orchestration-services`, `pe-console-services`, `pe-bolt-server` and `puppetdb`, the directory structure follows the following conventions. The value for `<service>` will be one of: `puppetserver`, `orchestration-services`, `console-services`, `bolt-server`, or `puppetdb`. The full path is always available inside the container as the environment variable `$SSLDIR`

- 'ssl-ca-cert'
  `/opt/puppetlabs/server/data/<service>/certs/certs/ca.pem`

- 'ssl-cert'
  `/opt/puppetlabs/server/data/<service>/certs/certs/server.crt`

- 'ssl-key'
  `/opt/puppetlabs/server/data/<service>/certs/private_keys/server.key`

The Postgres container pathing is slightly different and cannot follow the same pathing structure due to the design of the Postgres container. Paths for Postgres are typically:

- 'ssl-ca-cert'
  `/var/lib/postgresql/data/certs/certs/ca.pem`

- 'ssl-cert'
  `/var/lib/postgresql/data/certs/certs/server.crt`

- 'ssl-key'
  `/var/lib/postgresql/data/certs/private_keys/server.key`

NOTE: The files at these paths are copied to the location that Postgres is configured to use when the container starts (details in prior section).

# Additional Information

See https://github.com/puppetlabs/pupperware for more information.
