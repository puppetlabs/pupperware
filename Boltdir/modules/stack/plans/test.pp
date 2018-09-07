# A simple plan to run some tests against the stack
#
# To use this plan, you need the following:
#
# 1) A Linux (CentOS 7) host with docker-compose installed on it; that host
#    must be aliased to 'docker' in your .ssh/config
#
# 2) A Linux (CentOS 7) host with the puppet agent installed on it; after
#    agent installation, run 'puppet config set server DOCKER --section
#    agent' where DOCKER is the name under which this host can reach the
#    docker host from (1) You also need to set 'ForwardAgent yes' in your
#    .ssh/config for this host.
#
# This plan can be run from any machine that has bolt installed and can
# reach the hosts from (1) and (2) via ssh. To run this plan, cd into the
# toplevel pupperware directory and run
#
#    bolt plan run --tty stack::test
#
plan stack::test {
  # Rather than do a lot of logic in this plan to check for failures,
  # the tasks perform checks and fail if they encounter an unexpected
  # result.

  # Check out/update pupperware
  run_task(stack::clone, master)

  # Start the stack
  run_task(stack::manage, master, action => up, wait => true)

  # Put down some trivial puppet code
  run_task(stack::create_code, master)

  # Run the agent and check that it did something
  # We would like to pass '_tty' => true or some such here to force
  # allocation of a tty but that seems to not be possible. We need the
  # tty since default CentOS requires one for sudo
  run_task(stack::run_agent, agents, '_run_as' => 'root')

  # Stop and start the stack
  run_task(stack::manage, master, action => down)

  run_task(stack::manage, master, action => up, wait => true)

  # Run the agent again
  run_task(stack::run_agent, agents, '_run_as' => 'root')
}
