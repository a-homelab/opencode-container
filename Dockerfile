# syntax=docker/dockerfile:1

ARG UV_VERSION=0.12.17
ARG OPENCODE_VERSION=2.0.11
ARG BUN_VERSION=1.3.14
ARG IMAGEGEN_REVISION=57b3a14c2ec47a71fb67e4d696aeae9c355f7e4a

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM scratch AS opencode-amd64
ARG OPENCODE_VERSION
ADD https://registry.npmjs.org/@opencode/cli-linux-x64-baseline/-/cli-linux-x64-baseline-${OPENCODE_VERSION}.tgz /opencode.tgz

FROM scratch AS opencode-arm64
ARG OPENCODE_VERSION
ADD https://registry.npmjs.org/@opencode/cli-linux-arm64/-/cli-linux-arm64-${OPENCODE_VERSION}.tgz /opencode.tgz

FROM opencode-${TARGETARCH} AS opencode

FROM scratch AS imagegen-source
ARG IMAGEGEN_REVISION
ADD https://github.com/a-homelab/opencode-gpt-imagegen/archive/${IMAGEGEN_REVISION}.tar.gz /imagegen.tar.gz

FROM --platform=$BUILDPLATFORM oven/bun:${BUN_VERSION} AS imagegen
WORKDIR /build
COPY --from=imagegen-source /imagegen.tar.gz /tmp/imagegen.tar.gz
RUN tar -xzf /tmp/imagegen.tar.gz --strip-components=1 \
    && bun install --frozen-lockfile \
    && bun build ./src/index.ts --outfile /out/index.js \
      --target bun --format esm --packages bundle \
    && cp LICENSE /out/LICENSE

FROM debian:stable-slim AS build

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      ca-certificates \
      gzip \
      python3 \
      tar

COPY --from=uv /uv /uvx /usr/local/bin/
COPY toolkit/pyproject.toml toolkit/uv.lock /opt/agent-toolkit/
RUN UV_PYTHON_DOWNLOADS=never uv sync --locked --no-editable \
      --python /usr/bin/python3 --project /opt/agent-toolkit --compile-bytecode

COPY --from=opencode /opencode.tgz /tmp/opencode.tgz
RUN tar -xzf /tmp/opencode.tgz -C /tmp \
    && install -Dm755 /tmp/package/bin/opencode /usr/local/bin/opencode

    
FROM debian:stable-slim AS runtime

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
      bash \
      ca-certificates \
      coreutils \
      curl \
      dash \
      diffutils \
      findutils \
      gh \
      git \
      grep \
      gzip \
      jq \
      libstdc++6 \
      openssl \
      patch \
      python3 \
      rclone \
      ripgrep \
      sed \
      tar \
      tzdata \
    && rm -rf /var/lib/apt/lists/*

ARG OPENCODE_VERSION
ARG IMAGEGEN_REVISION

RUN groupadd --gid 65532 opencode \
    && useradd --uid 65532 --gid 65532 --no-log-init --no-create-home \
      --home-dir /state --shell /bin/bash opencode \
    && install -d -o 65532 -g 65532 /state /workspace

LABEL org.opencontainers.image.title="opencode-container" \
      org.opencontainers.image.description="OpenCode v2 with Git, GitHub CLI and authoring tools" \
      org.opencontainers.image.source="https://github.com/a-homelab/opencode-container" \
      org.opencontainers.image.version="${OPENCODE_VERSION}" \
      io.a-homelab.imagegen.revision="${IMAGEGEN_REVISION}"

COPY --from=build /usr/local/bin/opencode /usr/local/bin/opencode
COPY --from=uv /uv /uvx /usr/local/bin/
COPY --from=build /opt/agent-toolkit/ /opt/agent-toolkit/
COPY config/AGENTS.md /opt/opencode-defaults/AGENTS.md
COPY config/opencode.json /opt/opencode-defaults/opencode.json
COPY --from=imagegen /out/ /opt/opencode-plugins/imagegen/

ENV OPENCODE_CONFIG_DIR=/opt/opencode-defaults \
    HOME=/state \
    XDG_CONFIG_HOME=/state/config \
    XDG_DATA_HOME=/state/data \
    XDG_CACHE_HOME=/state/cache \
    XDG_STATE_HOME=/state/state \
    SHELL=/bin/bash \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_CACHE_DIR=/state/cache/uv \
    UV_LINK_MODE=copy

USER 65532:65532
WORKDIR /workspace
EXPOSE 4096

ENTRYPOINT ["/usr/local/bin/opencode"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "4096"]
