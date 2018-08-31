
# puppetstack

Run a container-based deployment of Puppet Infrastructure.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

Once you have Docker Compose installed, you can start the stack with
```
    DNS_ALT_NAMES=puppet,host.exmple.com docker-compose up -d
```

The value of `DNS_ALT_NAMES` must list all the names, as a comma-separated
list, under which the Puppet server in the stack can be reached from
agents. It must include `puppet` as that is used by PuppetDB to communicate
with the Puppet server. The value of `DNS_ALT_NAMES` only has an effect the
first time you start the stack, as it is placed into the server's SSL
certificate. If you need to change it after that, you will need to properly
revoke the server's certificate and restart the stack with the changed
`DNS_ALT_NAMES` value.

When you first start the Puppet Infrastructure, the stack will create a
number of directories to store the persistent data that should survive the
restart of your infrastructure. These directories are created right next to
the Docker Compose file:

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
* Note: On OSX, you must add the repository directory to "File Sharing" under
  `Preferences>File Sharing` in order for these directories to be created
  and volume-mounted automatically. There is no need to add each sub directory.

# Managing the stack

The script `bin/puppet` makes it easy to run `puppet` commands on the
puppet master. For example, `./bin/puppet config print autosign --section
master` prints the current setting for autosigning, which is `true` by
default. In a similar manner, any other task that you would perform on a
puppet master by running `puppet x y z ...` can be achieved against the
stack by running `./bin/puppet x y z ...`.

The script `bin/change-db-password` will change the postgresql database
password, rebuild the necessary containers, and restart all of the Puppet
Infrastructure containers. This script doesn't take any arguments and will
prompt you for all the needed information.
