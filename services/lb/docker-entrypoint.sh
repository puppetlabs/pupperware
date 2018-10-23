#! /bin/sh

# Master will cat public and private key into this file
cert=/etc/ssl/proxy_cert.pem

while [[ ! -f "$cert" ]]; do
    sleep 1
done

exec consul-template -config=/etc/haproxy.hcl
