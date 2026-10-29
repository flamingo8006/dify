# DGIST 운영 커스텀: dify-web 1.17.1 내장 Node.js 24.20.0 → 24.22.2 (Node.js 2026-10-21 보안 릴리스)
# 공식 node alpine 이미지의 node 바이너리만 교체한다. Next.js 산출물은 공식 이미지 그대로.
ARG BASE_IMAGE=langgenius/dify-web:1.17.1
ARG NODE_IMAGE=node:24.22.2-alpine

FROM ${NODE_IMAGE} AS node

FROM ${BASE_IMAGE}
ARG NODE_VERSION=24.22.2

USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
# 베이스 alpine(musl·libstdc++)과의 호환을 빌드 시점에 확인한다.
RUN test "$(node --version)" = "v${NODE_VERSION}"
ENV NODE_VERSION=${NODE_VERSION}

USER dify
