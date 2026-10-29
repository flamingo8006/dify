# DGIST 운영 커스텀: dify-api 1.17.1 내장 Node.js 24.20.0 → 24.22.2 (Node.js 2026-10-21 보안 릴리스, CVE-2026-111497 등)
# 공식 이미지 위에서 nodejs 패키지만 교체한다. 앱 코드·Python 의존성은 공식 이미지 그대로.
# api · api_websocket · worker · worker_beat 가 이 이미지를 공유한다.
ARG BASE_IMAGE=langgenius/dify-api:1.17.1
FROM ${BASE_IMAGE}

# 공식 이미지에 NodeSource 저장소(node_24.x)와 서명 키(지문 검증 완료)가 이미 설정돼 있다.
ARG NODE_PACKAGE_VERSION=24.22.2-1nodesource1

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends --only-upgrade "nodejs=${NODE_PACKAGE_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    && node --version

USER dify
