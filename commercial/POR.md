# Plan of Record for Pupperware

## Meta

This is the Plan of Record for Pupperware. We're using git to track high level
objectives and the plan coming in from product management. The purpose of
putting it in git is to capture changes and keep it close to developers.

## Current Sprint


# Overall Plan

Phase 0 and 0.5 relate to containerizing open source platform components. The goal of the phased approach below is that each phase addresses a specific use case. Each phase should result in a release so that we can get customer feedback sooner and iterate.

## Phase 0
### [Containerized Platform Components](https://tickets.puppetlabs.com/browse/PC-456)

  * [x] Containerize core Puppet components. This phase supports a new install of Platform.
  * [x] Core components are containerized
  * [x] Components functioning together on single host
  * [x] Puppet runs successfully
  * [x] Agents can get their catalog
  * [x] Data persists when containers exit
  * [x] Uses standard docker commands
  * [x] Works on Windows
  * [x] Testing enabled for PRs
  * [x] Testing is automated
  * [x] Use `docker-compose pull` to get updates
  * [x] Send an announcement to the open source community
  * [x] Able to change Postgresql passwords

## Phase 1
### [Containerize core PE components. This phase supports a new install of PE.](https://tickets.puppetlabs.com/browse/PC-719)

  * [x] Data persists when containers exit
  * [x] Puppet agent runs successfully / acquire catalog (tested in Pupperware via compose + rake specs)
  * [x] Tests can be run locally
  * [ ] Document docker versions and compose versions (3) (as a comment in the YAML) that are supported, operator instructions. Update the README.
  * [ ] Core PE components are containerized (excludes razor, HA, file sync)
  * [ ] Core PE Components functioning together on single host (via compose / swarm)
  * [ ] Able to install with max 2 commands on a single host
  * [ ] Create security model/opinion on if/how we care about service to service SSL, credential handling, private networks, cert sharing, etc
  * [ ] Works on Windows
  * [ ] Docker volume exist for storage
  * [ ] Agent container in play (+ Windows agent)

## Phase 2:
### [Support for updating](https://tickets.puppetlabs.com/browse/PC-720)

  * [ ] Users can update their PE version smoothly with one or two commands
  * [ ] You don’t lose data after updates (PE configuration data, certs, database stuff, classification, code, hiera, etc)
  * [ ] Upgrading defaults to latest in the stream you’re on, you must opt in to new major upgrades/streams
  * [ ] Users can specify an LTS track so they only get LTS updates (channel selection)

## Phase 3
### [Add compile masters and MoM](https://tickets.puppetlabs.com/browse/PC-721)
  * [ ] Optimize single node compile master deployment (why scale when we could just do the right thing at launch?)
  * [ ] Able to add a containerized compile master and MoM
  * [ ] Able to use `docker-compose scale` to scale compile masters

## Phase 4
### [Add migration support to migrate from a legacy PE master to containerized PE master](https://tickets.puppetlabs.com/browse/PC-724)

## Phase 5
### [Add support to migrate from open source Puppet to PE](https://tickets.puppetlabs.com/browse/PC-728)

  * [ ] Open source users can add a PE license key and PE components are turned on
  * [ ] Add analytics

## Phase 6
### Container Optimizations

Note :warning: We have moved this to later as it's optimizations that can be done any time. Originally this phase was to fill the gap between phase 0 completion and the rest of the Platerprise crew coming online to containers (from Johnson). That gap turned out to be smaller than anticipated.

  * [ ] Unnecessary artifacts are removed from each component for the final container build (multi stage builds) where applicable
  * [ ] Components are redesigned to be more efficient for containers where applicable (strip out any underlying mechanics that are not needed in a containerized environment)

## Phase 7 (line items need more customer validation)
### Add support for multiple hosts

 * [ ] Allows user-managed replication and HA
 * [ ] Use Swarm/Kubernetes for rolling updates and rollback support
 * [ ] Does PostgreSQL listen on the host network on only privately?
 * [ ] Do we expose PuppetDB endpoints publicly?
 * [ ] Audit for security, ports, interactions via mounts, configs, secrets

# Other stuff
### Possible additions

  * [ ] Add support for Time to Automation
  * [ ] Users can turn on individual PE components as they ramp up through Time to Automation
  * [ ] We have a licensing model that supports some components, not all
  * [ ] Distribute to select users for feedback. Demo to Home Depot.
  * [ ] Q: r10k is containerized but not in the compose file. Should we include PDK in the same container as r10k, but leave it up to the user to get that container (not part of the compose file)? (Defer until server team can take a look)


### Beta customers

  * Home Depot - main areas of interest are faster/smoother upgrades, and scaling.
  * WWT - main areas of interest are testing locally, easier upgrades, containerized compile masters

