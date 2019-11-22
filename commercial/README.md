# pupperware-commercial

Run a container-based deployment of Puppet Enterprise.

To get started, you will need an installation of
[Docker Compose](https://docs.docker.com/compose/install/) on the host on
which you will run your Puppet Infrastructure.

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [pupperware-commercial](#pupperware-commercial)
    - [Running](#running)
    - [Tests](#tests)
    - [Local Configuration](#local-configuration)
    - [Code Manager Setup](#code-manager-setup)
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

## Local Configuration

Create a `docker-compose.override.yml` file to add or override the
docker-compose configuration. This file is git ignored for your convenience.

Files to volume mount can be placed in a directory named `volumes/` at the root
of this repository, which is also git ignored.

## Code Manager Setup

To specify a control repo, define the `R10K_REMOTE` environment variable on the
`puppet` service.

If the control repo is private, SSH can be configured to access it. The
`R10K_REMOTE` URL should use the SSH protocol, such as
`git@github.com:user/repo.git`.

In addition, an SSH key named `id-control_repo.rsa` must be generated and
supplied to the `puppet` service via a volume mount at
`/etc/puppetlabs/puppetserver/ssh`. The public key needs to be added to the
control repo configuration (on GitHub, or wherever it's hosted).
Any additional SSH configuration files found in the volume will be used as is.

## Additional Information

See https://github.com/puppetlabs/pupperware for more information.
