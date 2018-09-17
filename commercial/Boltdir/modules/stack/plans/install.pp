# A plan to install Docker Compose on the master node, and the Puppet Agent
# on the agent node(s)
#
# Before using this plan, read the setup instructions under 'Running tests`
# in README.md
#
# Run this plan with
#
#    bolt plan run --tty stack::install
#
plan stack::install {
  $docker = run_task(stack::install_docker, master)
  $docker_ip = $docker.first()["ip"]
  $docker_host = $docker.first()["host"]

  run_task(stack::install_agent, agents,
             docker_ip => "${docker_ip}",
             docker_host => "${docker_host}")
}
