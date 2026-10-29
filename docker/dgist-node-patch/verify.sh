#!/usr/bin/env bash
# DGIST 운영 커스텀: 실행 중인 Dify 컨테이너의 이미지·상태·Node 버전 확인 (읽기 전용)
# 사용: cd /app/dify/docker && bash dgist-node-patch/verify.sh <compose 프로젝트명> [overlay|official]
#   overlay(기본): 오버레이 이미지 + Node ≥ 24.22.1 기대 · official: 롤백 후 공식 이미지 기대
set -uo pipefail

PROJECT="${1:?compose 프로젝트명을 지정하세요 (운영 docker · dev dify)}"
EXPECT="${2:-overlay}"
MIN_NODE=24.22.1
HEALTH_WAIT_SECONDS=180
dc() { docker compose -p "$PROJECT" "$@"; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

expected_image() {
  local svc="$1"
  if [ "$EXPECT" = official ]; then
    case "$svc" in
      api|api_websocket|worker|worker_beat) echo langgenius/dify-api:1.17.1 ;;
      web) echo langgenius/dify-web:1.17.1 ;;
      local_sandbox) echo langgenius/dify-agent-local-sandbox:1.17.1 ;;
      sandbox) echo langgenius/dify-sandbox:0.2.15 ;;
    esac
  else
    case "$svc" in
      api|api_websocket|worker|worker_beat) echo localhost/dgist/dify-api:1.17.1-node24.22.2 ;;
      web) echo localhost/dgist/dify-web:1.17.1-node24.22.2 ;;
      local_sandbox) echo localhost/dgist/dify-agent-local-sandbox:1.17.1-node24.22.2 ;;
      sandbox) echo localhost/dgist/dify-sandbox:0.2.15-node24.22.2 ;;
    esac
  fi
}

# healthcheck 가 있는 컨테이너는 healthy 가 될 때까지 기다린다(starting 은 대기, unhealthy 는 실패)
wait_health() {
  local cid="$1" deadline=$((SECONDS + HEALTH_WAIT_SECONDS)) h
  while :; do
    h="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null)" || return 1
    case "$h" in
      healthy|none) echo "$h"; return 0 ;;
      starting) [ "$SECONDS" -lt "$deadline" ] || { echo "$h"; return 1; }; sleep 5 ;;
      *) echo "$h"; return 1 ;;
    esac
  done
}

services=(api worker worker_beat web local_sandbox sandbox)
# api_websocket 은 collaboration 프로필 전용 — 컨테이너가 있으면(중지 포함) 검사 대상에 넣는다.
# 원래 쓰던 컨테이너가 아예 사라진 경우까지 잡으려면 EXPECT_WEBSOCKET=1 로 실행한다.
if [ -n "$(dc ps -a -q api_websocket 2>/dev/null)" ] || [ "${EXPECT_WEBSOCKET:-0}" = 1 ]; then
  services+=(api_websocket)
fi

fail=0
for svc in "${services[@]}"; do
  cid="$(dc ps -q "$svc" 2>/dev/null)"
  if [ -z "$cid" ]; then echo "FAIL $svc: 실행 중인 컨테이너 없음"; fail=1; continue; fi

  image="$(docker inspect --format '{{.Config.Image}}' "$cid" 2>/dev/null)"
  state="$(docker inspect --format '{{.State.Status}} restarts={{.RestartCount}}' "$cid" 2>/dev/null)"
  health="$(wait_health "$cid")"; health_rc=$?
  ver="$(docker exec "$cid" node --version 2>/dev/null | tr -d 'v\r')"
  # official(롤백 확인)은 버전을 기록만 한다
  ver_ok=0
  if [ "$EXPECT" = overlay ] && ! { [ -n "$ver" ] && version_ge "$ver" "$MIN_NODE"; }; then ver_ok=1; fi

  reasons=()
  [ "$image" = "$(expected_image "$svc")" ] || reasons+=("image")
  [[ "$state" == running* ]] || reasons+=("state")
  [ "$health_rc" -eq 0 ] || reasons+=("health")
  [ "$ver_ok" -eq 0 ] || reasons+=("node")
  if [ "${#reasons[@]}" -eq 0 ]; then res=OK; else res="FAIL(${reasons[*]})"; fail=1; fi
  echo "$res $svc node=v${ver:-?} $state health=$health $image"
done

# sandbox: 구 Node 20 잔존 여부 (기동 시 tarball 을 풀기 때문에 /opt 를 본다)
if [ "$EXPECT" = overlay ]; then
  sid="$(dc ps -q sandbox 2>/dev/null)"
  if [ -n "$sid" ] && left="$(docker exec "$sid" sh -c 'ls -d /opt/node-v20* 2>/dev/null | wc -l' 2>/dev/null)"; then
    left="$(echo "$left" | tr -d ' \r')"
    if [ "$left" = "0" ]; then echo "OK sandbox /opt node-v20 잔존 0"; else echo "FAIL sandbox /opt node-v20 잔존 $left"; fail=1; fi
  else
    echo "FAIL sandbox /opt 검사 실행 실패"; fail=1
  fi
fi

exit "$fail"
