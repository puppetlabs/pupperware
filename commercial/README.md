
# puppetstack

Run a container-based deployment of Puppet Infrastructure.

# DNS Stuff

You should make the host where docker-compose is running respond to a CNAME of
puppet, or put that in /etc/hosts on your clients. This is a known setup
requirement at this time.


# Examples

    docker-compose up -d


To scale out more puppet-server

    docker-compose scale puppet=2

To scale down

    docker-compose scale puppet=1


Tada!

