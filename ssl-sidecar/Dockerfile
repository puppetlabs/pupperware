FROM alpine:3.9
ARG vcs_ref
ARG build_date
ARG version="latest"
ENV PACKAGES "gettext curl openssl ca-certificates"

LABEL org.label-schema.maintainer="Puppet Release Team <release@puppet.com>" \
      org.label-schema.vendor="Puppet" \
      org.label-schema.url="https://github.com/puppetlabs/pupperware" \
      org.label-schema.name="SSL Sidecar" \
      org.label-schema.license="Apache-2.0" \
      org.label-schema.version="$version" \
      org.label-schema.vcs-url="https://github.com/puppetlabs/pupperware" \
      org.label-schema.vcs-ref="$vcs_ref" \
      org.label-schema.build-date="$build_date" \
      org.label-schema.schema-version="1.0" \
      org.label-schema.dockerfile="/Dockerfile"

RUN apk add --no-cache $PACKAGES
COPY shared/ssl.sh /ssl.sh
COPY ssl-sidecar/getcerts.sh /getcerts.sh
ENTRYPOINT ["/getcerts.sh"]

COPY ssl-sidecar/Dockerfile /
