# docker build -t local/puppetserver .
FROM puppet/puppetserver

COPY docker-entrypoint.d /docker-entrypoint.d

# We do not use https
HEALTHCHECK --interval=10s --timeout=10s --retries=90 CMD \
  curl --fail -H 'Accept: pson' \
  --resolve 'puppet:8140:127.0.0.1' \
  http://puppet:8140/${PUPPET_HEALTHCHECK_ENVIRONMENT}/status/test \
  |  grep -q '"is_alive":true' \
  || exit 1
