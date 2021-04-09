pupperware-commercial-dev

Run a container-based development environment of Puppet Enterprise.

## STATUS
Pre-alpha.  Nothing works yet.
Planned structure: adding an extra config file: console-services-dev.yml in this dir that can be run with the normal docker-compose.yml for pupperware.
e.g.
~~~
docker-compose -f docker-compose.yml -f dev/console-services-dev.yml
~~~
We will add an image that will mount the [pe-console-ui](https://github.com/puppetlabs/pe-console-ui) repo as a volume, and run 'ember build' and 'lein pe'.
This image will then support running tests, running with a filter, and running tests with a server (--launch=false).

Next steps:
1. WIP - Update pupperware-commercial supporting images to the latest versions and test that it works.
2. NOT STARTED - Create a base image for the dev system with volume mount
3. NOT STARTED - Refine the cert-stealer script to be fully automated in this environmen

Longer term plans:
1. Support different versions for images in the cluster
2. Support source-based images
