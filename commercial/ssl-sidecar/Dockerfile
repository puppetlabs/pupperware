FROM alpine:3.9
ENV PACKAGES "gettext curl openssl ca-certificates"
RUN apk add --update $PACKAGES && rm -rf /var/cache/apk/*
COPY shared/ssl.sh /ssl.sh
COPY shared/getcerts.sh /getcerts.sh
ENTRYPOINT ["/getcerts.sh"]
