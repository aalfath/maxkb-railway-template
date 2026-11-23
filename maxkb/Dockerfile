# MaxKB for Railway: the official image, pinned by version and digest.
# Postgres (pgvector) and Redis run as separate Railway services, so the
# PostgreSQL and Redis servers bundled in this image stay off.
FROM 1panel/maxkb:v2.10.9-lts@sha256:97810f4263ae95606322aa5786d6efc50891a7bccb7536368f04988d517f2701

# Clear the image's public default passwords: the template supplies generated ones.
ENV POSTGRES_PASSWORD= \
    REDIS_PASSWORD= \
    MAXKB_DB_PASSWORD= \
    MAXKB_REDIS_PASSWORD=

COPY --chmod=500 railway-start.sh /usr/bin/railway-start.sh

EXPOSE 8080
VOLUME /opt/maxkb
ENTRYPOINT ["/usr/bin/railway-start.sh"]
