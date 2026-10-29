# DGIST 운영 커스텀: dify-sandbox 0.2.15 내장 Node.js 20.20.0(EOL) → 24.22.2 (Node.js 2026-10-21 보안 릴리스)
# 업스트림 main(1b501ff1)도 같은 교체를 했지만 이미지 빌드가 실패해 릴리스가 없다.
# 공식 entrypoint 는 기동 때마다 $NODE_TAR_XZ 를 /opt 에 풀고 $NODE_DIR/bin/node 를
# /usr/local/bin/node 로 링크한 뒤 tarball 을 지운다 → tarball 과 두 ENV 만 바꾸면 된다.
ARG BASE_IMAGE=langgenius/dify-sandbox:0.2.15

FROM debian:bookworm-slim AS node
ARG NODE_VERSION=24.22.2
ARG TARGETARCH
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && case "${TARGETARCH}" in \
        amd64) node_arch="x64" ;; \
        arm64) node_arch="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && node_dist="node-v${NODE_VERSION}-linux-${node_arch}" \
    && mkdir /dist \
    && cd /dist \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${node_dist}.tar.xz" \
    && grep " ${node_dist}.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
    && rm SHASUMS256.txt

FROM ${BASE_IMAGE}
ARG NODE_VERSION=24.22.2
ARG TARGETARCH

# 구 Node 20 tarball 을 지워야 기동 시 다시 풀리지 않는다.
RUN rm -f /opt/node-v20.*.tar.xz && rm -rf /opt/node-v20.*
COPY --from=node /dist/ /opt/
ENV NODE_TAR_XZ=/opt/node-v${NODE_VERSION}-linux-x64.tar.xz \
    NODE_DIR=/opt/node-v${NODE_VERSION}-linux-x64
RUN test "${TARGETARCH}" = "amd64" \
    && test -f "${NODE_TAR_XZ}" \
    && ! ls /opt/node-v20.* >/dev/null 2>&1
