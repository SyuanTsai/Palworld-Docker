FROM palserver/agent:latest

USER root

COPY patch-internal-rest.mjs /tmp/patch-internal-rest.mjs
RUN node /tmp/patch-internal-rest.mjs \
    && rm /tmp/patch-internal-rest.mjs
