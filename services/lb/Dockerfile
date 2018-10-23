FROM haproxy:alpine

ENV CONSUL_TEMPLATE_VERSION=0.19.5

# HAProxy management port; not needed
# EXPOSE 8765

# Puppetserver
EXPOSE 8140
# Statistics page
EXPOSE 9000

RUN wget https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.tgz \
  && tar xfz consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.tgz \
  && mv consul-template /usr/bin/consul-template \
  && rm consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.tgz

COPY haproxy.tpl /usr/local/etc/haproxy/haproxy.tpl
COPY Dockerfile /
COPY docker-entrypoint.sh /
COPY haproxy.hcl /etc

ENTRYPOINT ["/docker-entrypoint.sh"]
