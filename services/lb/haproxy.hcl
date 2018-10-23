consul {
  address = "consul:8500"
}

template {
  source = "/usr/local/etc/haproxy/haproxy.tpl"
  destination = "/usr/local/etc/haproxy/haproxy.cfg"
}

exec {
  command = "haproxy -W -f /usr/local/etc/haproxy/haproxy.cfg"
  reload_signal = "SIGUSR2"
  kill_signal = "SIGUSR1"
}
