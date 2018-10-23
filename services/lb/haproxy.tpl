# -*- conf -*-
global
  # admin socket, not needed
  # stats socket ipv4@*:8765 level admin
  tune.ssl.default-dh-param 2048
  log /var/run/rsyslog/dev/log local0
  log /var/run/rsyslog/dev/log local1
  maxconn 50

defaults
  mode http
  option httplog
  timeout connect 5000
  timeout check 5000
  timeout client 30000
  timeout server 30000

listen stats # Define a listen section called "stats"
  bind *:9000 # Listen on localhost:9000
  stats enable  # Enable stats page
  stats hide-version  # Hide HAProxy version
  stats realm Haproxy\ Statistics  # Title text for popup window
  stats uri /  # Stats URI
  log global

#---------------------------------------------------------------------
# frontend with SSL termination
# see https://github.com/vshn/puppet-in-docker/blob/master/haproxy/haproxy.tmpl
#---------------------------------------------------------------------
frontend puppet
  bind *:8140 ssl ca-file /etc/ssl/certs/ca.pem crt /etc/ssl/proxy_cert.pem verify optional crl-file /etc/ssl/crl.pem
  acl is_ca_uri path_beg "/puppet-ca/"
  http-request set-header X-Client-Verify-Real  %[ssl_c_verify]
  http-request set-header X-Client-Verify NONE if !{ hdr_val(X-Client-Verify-Real) eq 0 }
  http-request set-header X-Client-Verify SUCCESS if { hdr_val(X-Client-Verify-Real) eq 0 }
  http-request set-header X-Client-DN     CN=%{+Q}[ssl_c_s_dn(cn)]
  http-request set-header X-Client-Cert   "-----BEGIN CERTIFICATE-----%%0A%[ssl_c_der,base64]%%0A-----END CERTIFICATE----- #" if { ssl_c_used }
  use_backend ca if is_ca_uri
  default_backend puppets
  log global

backend ca
    server master "master:8140" check port 8140 inter 5s

backend puppets
    balance     roundrobin
    server master master:8140 check port 8140 inter 5s
    {{ range $i, $ip := ls "services/compiler" -}}
      server compiler{{ add $i 1 }} {{ .Key }}:8140 check port 8140 inter 5s
    {{ end -}}
