#!/bin/sh
#
# Get a signed certificate for this host.
#
# Uses OpenSSL directly to generate a new CSR and get it signed by the
# Puppet Server CA.
#
# Intended to be used in place of a full-blown puppet agent run that is solely
# for getting SSL certificates onto the host.
#
# Files will be placed in the same default directory location and structure
# that the puppet agent would put them, which is /etc/puppetlabs/puppet/ssl,
# unless the SSLDIR environment variable is specified.
#
# The certname is provided as the CERTNAME environment variable. If not found,
# the HOSTNAME will be used.
#
# Supports DNS alt names via the DNS_ALT_NAMES environment variable, which
# is a comma-separated string of names. The Puppet Server CA must be configured
# to allow subject alt names, by default it will reject certificate requests
# with them.
#
# Optional environment variables:
#   CERTNAME               Certname to use
#   WAITFORCERT            Number of seconds to wait for certificate to be
#                          signed, defaults to 300
#   PUPPETSERVER_HOSTNAME  Hostname of Puppet Server CA, defaults to "puppet"
#   PUPPETSERVER_PORT      Port of Puppet Server CA, defaults to 8140
#   SSLDIR                 Root directory to write files to, defaults to
#                          "/etc/puppetlabs/puppet/ssl"
#   DNS_ALT_NAMES          Comma-separated string of DNS subject alternative
#                          names, defaults to none

msg() {
    echo "($0) $1"
}

error() {
    msg "Error: $1"
    exit 1
}

# builds the GET http request given a URI
get() {
    printf "GET %s HTTP/1.0\n%s" "$1" "$HOSTHEADER"
}

# use openssl s_client to create HTTP requests and parse the response
# a 200 OK will set a 0 return value, all other responses are non-zero
# the HTTP response body is returned over stdout
# $1 is request value
httpsreq() {
    httpsreq_insecure "$1" "-CAfile ""${CACERTFILE}"""
}

# use openssl s_client to create HTTP requests and parse the response
# a 200 OK will set a 0 return value, all other responses are non-zero
# the HTTP response body is returned over stdout
# $1 is request value
# $2 is additional s_client CLI flags
httpsreq_insecure() {
    CLIENTFLAGS="-connect ""${PUPPETSERVER_HOSTNAME}:${PUPPETSERVER_PORT}"" -ign_eof -quiet $2"

    # shellcheck disable=SC2086 # $CLIENTFLAGS shouldn't be quoted
    if ! response=$(printf "%s\n\n" "$1" | openssl s_client ${CLIENTFLAGS} 2>/dev/null); then
        # possibly due to DNS errors or connnection refused
        return 1
    fi

    # an empty response doesn't include a status code, so abort
    [ -z "$response" ] && return 1

    # extract the HTTP status code from first line of response
    # RFC2616 defines first line header as Status-Line = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
    status=$(printf "%s" "$response" | head -1 | cut -d ' ' -f 2)

    # unparseable status line, so abort
    [ -z "$status" ] && return 1

    # write HTTP payload over stdout by collecting all lines after header\r
    # same as: awk -v bl=1 'bl{bl=0; h=($0 ~ /HTTP\/1/)} /^\r?$/{bl=1} {if(!h) print}'
    body=false
    printf "%s\n" "$response" | while read -r line
    do
        if [ $body = true ]; then
            printf '%s\n' "$line"
        # a lone CR means the separator between headers and body has been reached
        elif [ "$line" = "$(printf "\r")" ]; then
            body=true
        fi
    done

    # treat a 200 as 0 exit code
    [ "${status}" = "200" ] && return 0 || return "$((status))"
}

master_ca_running() {
    test "$(httpsreq_insecure "$(get '/status/v1/simple')")" = "running" && \
        httpsreq_insecure "$(get "${CA}/certificate/ca")" > /dev/null
}

### Verify we got a signed certificate
verify_cert() {
    if [ -f "${CERTFILE}" ] && [ "$(head -1 "${CERTFILE}")" = "${CERTHEADER}" ]; then
        altnames="-certopt no_subject,no_header,no_version,no_serial,no_signame,no_validity,no_issuer,no_pubkey,no_sigdump,no_aux"
        # shellcheck disable=SC2086 # $altnames shouldn't be quoted
        if openssl x509 -subject -issuer -text -noout -in "${CERTFILE}" $altnames; then
            msg "Successfully signed certificate '${CERTFILE}'"
        else
            error "invalid signed certificate '${CERTFILE}'"
        fi
    else
        error "failed to get signed certificate for '${CERTNAME}'"
    fi
}

### Verify dependencies available
! command -v openssl > /dev/null && error "openssl not found on PATH"

### Verify options are valid
# shellcheck disable=SC2039 # Docker injects $HOSTNAME
CERTNAME="${CERTNAME:-${HOSTNAME}}"
[ -z "${CERTNAME}" ] && error "certificate name must be non-empty value"
PUPPETSERVER_HOSTNAME="${PUPPETSERVER_HOSTNAME:-puppet}"
PUPPETSERVER_PORT="${PUPPETSERVER_PORT:-8140}"
SSLDIR="${SSLDIR:-/etc/puppetlabs/puppet/ssl}"
WAITFORCERT=${WAITFORCERT:-300}
DNS_ALT_NAMES=${DNS_ALT_NAMES:-}

### Create directories and files
PUBKEYDIR="${SSLDIR}/public_keys"
PRIVKEYDIR="${SSLDIR}/private_keys"
CSRDIR="${SSLDIR}/certificate_requests"
CERTDIR="${SSLDIR}/certs"
mkdir -p "${SSLDIR}" "${PUBKEYDIR}" "${PRIVKEYDIR}" "${CSRDIR}" "${CERTDIR}"
PUBKEYFILE="${PUBKEYDIR}/${CERTNAME}.pem"
CANONICAL_PUBKEYFILE="${PUBKEYDIR}/server.pub"
PRIVKEYFILE="${PRIVKEYDIR}/${CERTNAME}.pem"
CANONICAL_PRIVKEYFILE="${PRIVKEYDIR}/server.key"
CSRFILE="${CSRDIR}/${CERTNAME}.pem"
CERTFILE="${CERTDIR}/${CERTNAME}.pem"
CANONICAL_CERTFILE="${CERTDIR}/server.crt"
CACERTFILE="${CERTDIR}/ca.pem"
CRLFILE="${SSLDIR}/crl.pem"
ALTNAMEFILE="/tmp/altnames.conf"

CA="/puppet-ca/v1"
CERTSUBJECT="/CN=${CERTNAME}"
CERTHEADER="-----BEGIN CERTIFICATE-----"
HOSTHEADER="Host: ${PUPPETSERVER_HOSTNAME}"

### Handle certificate extensions
# NOTE If we want to expand support for more extensions, it would be better
# to define them in a .conf file rather than directly on the CLI.
# That would also work on older versions of openssl that don't support
# the `-addext` flag.
# For now, we explicitly handle DNS alt names because it's simpler.
CERTEXTENSIONS=""
if [ -n "${DNS_ALT_NAMES}" ]; then
    names=""
    first=true
    for name in $(printf "%s" "${DNS_ALT_NAMES}" | tr "," " "); do
        if $first; then
            first=false
            names="DNS:${name}"
        else
            names="${names},DNS:${name}"
        fi
    done

    # openssl 1.1.1+ supports -addext subjectAltName=${names}
    # previously used Postgres 9.6 image uses openssl 1.1.0 and has no such flag, so have to use -config
    # postgres 12.4 has openssl 1.1.1d
    printf "[req]\ndistinguished_name=dn\nreq_extensions=ext\n[dn]\n[ext]\nsubjectAltName=%s\n" "${names}" > "${ALTNAMEFILE}"

    CERTEXTENSIONS="-config ${ALTNAMEFILE}"
fi

### Print configuration for troubleshooting
msg "Using configuration values:"
# shellcheck disable=SC2039 # Docker injects $HOSTNAME
msg "* HOSTNAME: '${HOSTNAME}'"
msg "* hostname -f: '$(hostname -f)'"
msg "* CERTNAME: '${CERTNAME}' (${CERTSUBJECT})"
msg "* DNS_ALT_NAMES: '${DNS_ALT_NAMES}'"
msg "* CA: '${PUPPETSERVER_HOSTNAME}:${PUPPETSERVER_PORT}${CA}'"
msg "* SSLDIR: '${SSLDIR}'"
msg "* WAITFORCERT: '${WAITFORCERT}' seconds"

if [ -s "${CERTFILE}" ]; then
    msg "Certificates have already been generated - exiting!"
    exit 0
fi

msg "Waiting for master ${PUPPETSERVER_HOSTNAME} to be running to generate certificates..."
while ! master_ca_running; do
    sleep 1
done

### Get the CA certificate for use with subsequent requests
### Fail-fast if openssl errors connecting or the CA certificate can't be parsed
if ! httpsreq_insecure "$(get "${CA}/certificate/ca")" > "${CACERTFILE}"; then
    error "cannot reach CA host '${PUPPETSERVER_HOSTNAME}'"
elif ! openssl x509 -subject -issuer -noout -in "${CACERTFILE}"; then
    error "invalid CA certificate"
fi

### Get the CRL from the CA for use with client-side validation
if ! httpsreq "$(get "${CA}/certificate_revocation_list/ca")" > "${CRLFILE}"; then
    error "cannot reach CRL host '${PUPPETSERVER_HOSTNAME}'"
elif ! openssl crl -text -noout -in "${CRLFILE}" > /dev/null; then
    error "invalid CRL"
fi

### Check if the CA already has a signed certificate for this host to either:
### * Recover from a submitted CSR attempt that didn't complete
### * Abort if there are no generated files on disk (i.e. hostname exists / collision)
### * Abort if generated files don't match (i.e. hostname exists / collision)
CERTREQ=$(get "${CA}/certificate/${CERTNAME}")
if cert=$(httpsreq "$CERTREQ"); then
    # if cert exists for name and disk is empty, this DNS name is claimed!
    [ ! -s "${PRIVKEYFILE}" ] && error "No keypair on disk and CA already has signed certificate for '${CERTNAME}'"

    # private key file exists, so see if a CSR was submitted but never signed
    key_hash=$(openssl rsa –noout –modulus –in "${PRIVKEYFILE}" 2> /dev/null | openssl md5)
    cert_hash=$(echo "${cert}" | openssl x509 –noout –modulus 2> /dev/null | openssl md5)
    [ "${key_hash}" != "${cert_hash}" ] && error "Private key on disk does not match signed certificate for '${CERTNAME}'"

    # Signed cert matches private key, so write it to disk
    msg "Recovered from incomplete signing - retrieved signed certificate matching private key on disk"
    printf "%s\n" "${cert}" > "${CERTFILE}"
    # using a well known filename makes this easier to consume in k8s
    ln -s -f "${CERTFILE}" "${CANONICAL_CERTFILE}"

    verify_cert
    exit 0
fi

### Generate keys and CSR for this host
[ -s "${PRIVKEYFILE}" ] && error "private key '${PRIVKEYFILE}' already exists"
[ -s "${PUBKEYFILE}" ] && error "public key '${PUBKEYFILE}' already exists"
[ -s "${CSRFILE}" ] && error "certificate request '${CSRFILE}' already exists"
openssl genrsa -out "${PRIVKEYFILE}" 4096
# using a well known filename makes this easier to consume in k8s
ln -s -f "${PRIVKEYFILE}" "${CANONICAL_PRIVKEYFILE}"
openssl rsa -in "${PRIVKEYFILE}" -pubout -out "${PUBKEYFILE}"
# using a well known filename makes this easier to consume in k8s
ln -s -f "${PUBKEYFILE}" "${CANONICAL_PUBKEYFILE}"
# shellcheck disable=SC2086 # $CERTEXTENSIONS shouldn't be quoted
openssl req -new -key "${PRIVKEYFILE}" -out "${CSRFILE}" -subj "${CERTSUBJECT}" ${CERTEXTENSIONS}
[ -f "${ALTNAMEFILE}" ] && rm "${ALTNAMEFILE}"

### Submit CSR and fail gracefully on certain error conditions
CSRREQ=$(cat <<EOF
PUT ${CA}/certificate_request/${CERTNAME} HTTP/1.0
${HOSTHEADER}
Content-Length: $(wc -c < "${CSRFILE}")
Content-Type: text/plain

$(cat "${CSRFILE}")
EOF
)

sleeptime=3
timewaited=0
msg "Submitting CSR..."
while ! output=$(httpsreq "$CSRREQ"); do
    cert_already_exists="${CERTNAME} already has a requested certificate; ignoring certificate request"
    altnames_disallowed="CSR '${CERTNAME}' contains subject alternative names*which are disallowed*"
    # shellcheck disable=SC2254 # string contains * used for globbing
    case "${output}" in
        "$cert_already_exists") error "unsigned CSR for '${CERTNAME}' already exists on CA" ;;
        $altnames_disallowed) error "DNS Alt Names not allowed by the CA" ;;
        # ignore empty or unexpected responses and retry
        '') ;;
        *) msg "[WARNING] CSR response: ${output}" ;;
    esac

    [ ${timewaited} -ge $((WAITFORCERT)) ] && \
        error "timed-out waiting for certificate signing request to be accepted"

    sleep ${sleeptime}
    msg "Resubmitting CSR..."
    timewaited=$((timewaited+sleeptime))
done

### Retrieve signed certificate; wait and try again with a timeout
sleeptime=10
timewaited=0
while ! cert=$(httpsreq "$CERTREQ"); do
    [ ${timewaited} -ge $((WAITFORCERT)) ] && \
        error "timed-out waiting for certificate to be signed"
    msg "Waiting for certificate to be signed..."
    sleep ${sleeptime}
    timewaited=$((timewaited+sleeptime))
done
printf "%s\n" "${cert}" > "${CERTFILE}"
# using a well known filename makes this easier to consume in k8s
ln -s -f "${CERTFILE}" "${CANONICAL_CERTFILE}"

verify_cert
