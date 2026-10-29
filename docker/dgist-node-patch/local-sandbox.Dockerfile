# DGIST 운영 커스텀: dify-agent-local-sandbox 1.17.1 내장 Node.js 24.20.0 → 24.22.2 (Node.js 2026-10-21 보안 릴리스)
# 공식 이미지와 같은 방식(nodejs.org 배포본 + SHASUMS256 검증)으로 /usr/local 의 Node 만 교체한다.
ARG BASE_IMAGE=langgenius/dify-agent-local-sandbox:1.17.1

FROM debian:bookworm-slim AS node
ARG NODE_VERSION=24.22.2
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && case "${TARGETARCH}" in \
        amd64) node_arch="x64" ;; \
        arm64) node_arch="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && node_dist="node-v${NODE_VERSION}-linux-${node_arch}" \
    && cd /tmp \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${node_dist}.tar.xz" \
    && grep " ${node_dist}.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && mkdir /node \
    && tar -xJf "${node_dist}.tar.xz" -C /node --strip-components=1

FROM ${BASE_IMAGE}
ARG NODE_VERSION=24.22.2

USER root
# 번들 npm·corepack·헤더는 지우고 새 배포본으로 교체한다. 전역 설치한 pnpm 은 유지된다.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /usr/local/include/node
COPY --from=node /node/bin/ /usr/local/bin/
COPY --from=node /node/lib/ /usr/local/lib/
COPY --from=node /node/include/ /usr/local/include/
RUN test "$(node --version)" = "v${NODE_VERSION}" && npm --version && pnpm --version

USER dify
