
# puppetstack

Run a container-based deployment of Puppet Infrastructure.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

When you first start the Puppet Infrastructure with `docker-compose up`,
the stack will create a number of directories to store the persistent data
that should survive the restart of your infrastructure. These directories
are created right next to the Docker Compose file:

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

# DNS Stuff

Change the environment variable `DNS_ALT_NAMES` to list all the names under
which agents will try to reach the puppet master, for example, set it to
`DNS_ALT_NAMES=puppet,myhost.example.com`. Note that this setting only has
an effect when the Puppet Infrastructure is run for the first time, i.e.,
when it will generate a certificate for the puppetserver.


# Examples

    docker-compose up -d


To scale out more puppet-server

    docker-compose scale puppet=2

To scale down

    docker-compose scale puppet=1


Tada!
