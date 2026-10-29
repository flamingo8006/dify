#!/usr/bin/env bash
# DGIST 운영 커스텀: Node 24.22.2 오버레이 이미지 4종 빌드 (dev·운영 공통, 컨테이너는 건드리지 않음)
# 사용: cd /app/dify/docker && bash dgist-node-patch/build.sh
set -euo pipefail

cd "$(dirname "$0")"

NODE_VERSION=24.22.2
TAG_SUFFIX="node${NODE_VERSION}"

# 이미지명|Dockerfile|베이스 이미지
IMAGES=(
  "localhost/dgist/dify-api:1.17.1-${TAG_SUFFIX}|api.Dockerfile|langgenius/dify-api:1.17.1"
  "localhost/dgist/dify-web:1.17.1-${TAG_SUFFIX}|web.Dockerfile|langgenius/dify-web:1.17.1"
  "localhost/dgist/dify-agent-local-sandbox:1.17.1-${TAG_SUFFIX}|local-sandbox.Dockerfile|langgenius/dify-agent-local-sandbox:1.17.1"
  "localhost/dgist/dify-sandbox:0.2.15-${TAG_SUFFIX}|sandbox.Dockerfile|langgenius/dify-sandbox:0.2.15"
)

for entry in "${IMAGES[@]}"; do
  IFS='|' read -r image dockerfile base <<< "$entry"
  # 베이스는 서버에 이미 있는 공식 이미지를 쓴다. 없으면 받아오지 않고 멈춘다.
  if ! docker image inspect "$base" > /dev/null 2>&1; then
    echo "베이스 이미지 없음: $base — 중단" >&2
    exit 1
  fi
  echo "== build $image (base $(docker image inspect --format '{{index .RepoDigests 0}}' "$base"))"
  docker build -f "$dockerfile" --build-arg "BASE_IMAGE=$base" -t "$image" .
done

echo "== 결과"
for entry in "${IMAGES[@]}"; do
  IFS='|' read -r image _ _ <<< "$entry"
  printf '%s\t%s\n' "$image" "$(docker image inspect --format '{{.Id}}' "$image")"
done
