FROM postgres:9.6

ARG version
ARG vcs_ref
ARG build_date
LABEL org.label-schema.maintainer="Puppet Release Team <release@puppet.com>" \
      org.label-schema.vendor="Puppet" \
      org.label-schema.url="https://github.com/puppetlabs/pupperware-commercial" \
      org.label-schema.name="PE Postgres" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.version="$version" \
      org.label-schema.vcs-url="https://github.com/puppetlabs/pupperware-commercial" \
      org.label-schema.vcs-ref="$vcs_ref" \
      org.label-schema.build-date="$build_date" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

ENV POSTGRES_PASSWORD puppetdb
ENV POSTGRES_USER puppetdb
ENV POSTGRES_DB puppetdb

COPY config /etc/postgresql/config
COPY postgres-custom /docker-entrypoint-initdb.d

CMD ["postgres", \
    "-c", "hba_file=/etc/postgresql/config/pg_hba.conf", \
    "-c", "ident_file=/etc/postgresql/config/pg_ident.conf", \
    "-c", "ssl=on", \
    "-c", "ssl_cert_file=/etc/postgresql/ssl/certs/postgres.test.pem", \
    "-c", "ssl_key_file=/etc/postgresql/ssl/private_keys/postgres.test.pem", \
    "-c", "ssl_ca_file=/etc/postgresql/ssl/certs/ca.pem", \
    "-c", "max_connections=400"]

EXPOSE 5432

COPY Dockerfile /
