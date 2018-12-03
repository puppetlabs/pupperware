#!/bin/bash

# HAProxy wants a .pem file that contains both our private and public SSL certs
# To this end, initialize the CA explicitly and produce that file

[[ -z "$MAIN_PUPPET" ]] && exit 0

if [[ -z "${PUPPETSERVER_HOSTNAME}" ]]; then
    # the default certname (fqdn) is absolutly useless in our situation
    # we should either produce an error if PUPPETSERVER_HOSTNAME is not
    # set or default to the Docker host name
    echo "Please set PUPPETSERVER_HOSTNAME to the external name of the docker host"
    exit 1
fi

cd /etc/puppetlabs/puppet/ssl

CERTNAME="${PUPPETSERVER_HOSTNAME}"
if [[ ! -f ca/ca_key.pem ]]; then
    echo "initializing the CA"
    puppetserver ca setup --ca-name "Pupperware on $CERTNAME" \
                 --certname "$CERTNAME" --subject-alt-names "$DNS_ALT_NAMES"
fi

if [[ ! -s proxy_cert.pem ]]; then
    echo "creating HAProxy cert"
    # Create combined pem for HAProxy
    touch proxy_cert.pem
    chmod 0640 proxy_cert.pem
    cat certs/"$CERTNAME".pem private_keys/"$CERTNAME".pem > proxy_cert.pem
fi
