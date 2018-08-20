
# puppetstack

Run a container-based deployment of Puppet Infrastructure.

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
