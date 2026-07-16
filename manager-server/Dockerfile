FROM ghcr.io/pocketpairjp/palserver:latest

USER root

COPY manager-entrypoint.sh /usr/local/bin/manager-entrypoint.sh
RUN chmod 0755 /usr/local/bin/manager-entrypoint.sh \
    && rm -rf /pal/Package/Pal/Saved \
    && ln -s /data/saved /pal/Package/Pal/Saved

USER root

ENTRYPOINT ["/usr/local/bin/manager-entrypoint.sh"]
