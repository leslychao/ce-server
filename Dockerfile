FROM debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818

ARG STEAM_UID=1000
ARG STEAM_GID=1000

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/steam \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SERVER_DIR=/home/steam/server-files \
    STEAMCMD_BIN=/opt/steamcmd/steamcmd.sh

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        crudini \
        curl \
        lib32gcc-s1 \
        lib32stdc++6 \
        libatomic1 \
        libcurl4 \
        libicu72 \
        libssl3 \
        libunwind8 \
        procps \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${STEAM_GID}" steam \
    && useradd --uid "${STEAM_UID}" --gid "${STEAM_GID}" --create-home --shell /bin/bash steam \
    && mkdir -p /opt/steamcmd /home/steam/server-files \
    && curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
        -o /tmp/steamcmd_linux.tar.gz \
    && tar -xzf /tmp/steamcmd_linux.tar.gz -C /opt/steamcmd \
    && rm /tmp/steamcmd_linux.tar.gz \
    && chown -R steam:steam /opt/steamcmd /home/steam

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

USER steam
WORKDIR /home/steam

EXPOSE 7777/udp 7778/udp 27015/udp 25575/tcp

STOPSIGNAL SIGTERM

HEALTHCHECK --start-period=10m --interval=30s --timeout=5s --retries=3 \
  CMD pgrep -f '[C]onanSandboxServer-Linux-Shipping' >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
