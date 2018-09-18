# Return a hash of timestamps for the latest facts, catalog, and report
# stored in PuppetDB for the first agent in our inventory
function stack::pdb_timestamps() {
  $res1 = run_command("facter fqdn | tr -d [:space:]", agents)
  $agent = $res1.first()["stdout"]

  $res2 = run_task(stack::pdb_node, master, agent => $agent)

  $nd = $res2.first().value()["nodes"][0]
  $ts = {
    "facts" => Timestamp.new($nd["facts_timestamp"]),
    "catalog" => Timestamp.new($nd["catalog_timestamp"]),
    "report" => Timestamp.new($nd["report_timestamp"])
  }
  return $ts
}
