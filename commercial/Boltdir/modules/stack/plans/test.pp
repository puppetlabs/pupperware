# A simple plan to run some tests against the stack
#
# To use this plan, read the setup instructions under 'Running tests` in
# README.md
#
# Once everything is set up, you can run this plan with
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
  run_task(stack::run_agent, agents)

  $ts1 = stack::pdb_timestamps()

  # Stop and start the stack
  run_task(stack::manage, master, action => down)

  run_task(stack::manage, master, action => up, wait => true)

  # Run the agent again
  run_task(stack::run_agent, agents)

  $ts2 = stack::pdb_timestamps()

  # Check that timestamps changed
  ["facts", "catalog", "report"].each |$item| {
    # We check not just equality, but that the timestamps
    # moved in the right direction
    if $ts1[$item] >= $ts2[$item] {
      fail_plan("The timestamp for ${item} did not change after an agent run",
                "stack/timestamps-not-changed",
                { "item" => $item,
                  "before" => $ts1[$item],
                  "after" => $ts2[$item] })
    }
  }
}
