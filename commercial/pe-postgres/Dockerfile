FROM postgres:9.6

ARG version
ARG vcs_ref
ARG build_date

ENV POSTGRES_PASSWORD puppetdb
ENV POSTGRES_USER puppetdb
ENV POSTGRES_DB puppetdb
ENV SSLDIR /etc/postgresql/ssl
ENV CERTNAME postgres
ENV PE_CONSOLE_SERVICES_HOSTNAME pe-console-services
ENV PE_ORCHESTRATION_SERVICES_HOSTNAME pe-orchestration-services

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

RUN apt-get update && \
    apt-get install -y --no-install-recommends gettext && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY config /etc/postgresql/config
RUN chmod 777 /etc/postgresql/config
COPY postgres-custom /docker-entrypoint-initdb.d

CMD ["postgres", "-c", "config_file=/etc/postgresql/config/postgresql.conf"]

EXPOSE 5432

COPY Dockerfile /
