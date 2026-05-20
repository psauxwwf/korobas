ARG BASE_IMAGE=scottyhardy/docker-remote-desktop:latest
FROM ${BASE_IMAGE}

ARG KOROBAS_UID=1000
ARG KOROBAS_GID=1000
ARG KOROBAS_IMAGE=ghcr.io/psauxwwf/korobas-desktop:latest

USER root

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV GOPATH=/home/korobas/.go
ENV EDITOR=hx
ENV KOROBAS_IMAGE=${KOROBAS_IMAGE}

RUN set -eux; \
    apt-get update; \
    set -- \
        curl \
        ca-certificates \
        gosu \
        libatomic1 \
        openssh-server \
        sudo \
        zsh \
        stow \
        git \
        build-essential \
        iproute2 \
        procps \
        socat \
        fzf; \
    case "$KOROBAS_IMAGE" in *desktop*) \
        set -- "$@" torbrowser-launcher; \
    esac; \
    apt-get install --yes --no-install-recommends "$@"; \
    case "$KOROBAS_IMAGE" in *desktop*) \
        curl -fsSL https://github.com/throneproj/Throne/releases/download/1.1.2/Throne-1.1.2-debian-amd64-system-qt.deb -o /tmp/throne.deb; \
        apt-get install --yes /tmp/throne.deb; \
    esac; \
    curl -fsSL https://github.com/psauxwwf/proxychains/releases/latest/download/proxychains.tar.gz -o /tmp/proxychains.tar.gz; \
    tar -xzf /tmp/proxychains.tar.gz -C /; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd --gid "${KOROBAS_GID}" korobas \
    && usermod --shell /bin/bash root \
    && useradd --uid "${KOROBAS_UID}" --gid korobas --create-home --shell /bin/zsh korobas \
    && usermod --append --groups sudo korobas

RUN curl -fsSL https://mise.run -o /tmp/install-mise.sh \
    && MISE_INSTALL_PATH=/usr/local/bin/mise sh /tmp/install-mise.sh \
    && rm -f /tmp/install-mise.sh

# ENV MISE_CONFIG_DIR=/etc/mise
# ENV MISE_DATA_DIR=/home/korobas/.local/share/mise
# ENV MISE_SYSTEM_DATA_DIR=/usr/local/share/mise
# ENV MISE_CACHE_DIR=/home/korobas/.cache/mise
# ENV MISE_STATE_DIR=/home/korobas/.local/state/mise
# ENV MISE_HTTP_TIMEOUT=120
# ENV MISE_JOBS=1
ENV PATH="/home/korobas/.go/bin:\
/home/korobas/.local/bin:\
/home/korobas/.local/share/mise/shims:\
/usr/local/share/mise/shims:${PATH}"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

COPY sshd_config /etc/ssh/sshd_config

COPY sudoers_korobas /etc/sudoers.d/korobas

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && chmod 0644 /etc/ssh/sshd_config \
    && chmod 0440 /etc/sudoers.d/korobas

WORKDIR /home/korobas

EXPOSE 3389 22 8000 8082

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["sleep", "infinity"]
