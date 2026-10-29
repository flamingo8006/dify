# Dify Node.js 보안 패치 오버레이 (작업 ND · 2026-10)

Node.js 2026-10-21 보안 릴리스(CVE-2026-111497 Brotli OOB write 외 9건, 해결 v24.22.1, 완화책 없음)에 대응한다.
Dify 1.17.1을 유지하면서 공식 이미지에 내장된 Node만 **24.22.2**로 바꾼 이미지를 서버에서 빌드해 쓴다.

| 서비스 | 공식 이미지 | Node 전 → 후 | 오버레이 이미지 |
|---|---|---|---|
| api · api_websocket · worker · worker_beat | `langgenius/dify-api:1.17.1` | 24.20.0 → 24.22.2 | `localhost/dgist/dify-api:1.17.1-node24.22.2` |
| web | `langgenius/dify-web:1.17.1` | 24.20.0 → 24.22.2 | `localhost/dgist/dify-web:1.17.1-node24.22.2` |
| local_sandbox | `langgenius/dify-agent-local-sandbox:1.17.1` | 24.20.0 → 24.22.2 | `localhost/dgist/dify-agent-local-sandbox:1.17.1-node24.22.2` |
| sandbox | `langgenius/dify-sandbox:0.2.15` | 20.20.0(EOL) → 24.22.2 | `localhost/dgist/dify-sandbox:0.2.15-node24.22.2` |

- 앱 코드·Python 의존성·DB 스키마는 공식 이미지와 같고, 마이그레이션은 0건이다. 그래서 되돌리기는 이미지만 바꾸면 된다.
- 연결 방식: `docker/docker-compose.override.yaml`(compose가 자동으로 읽음)이 위 7개 서비스의 `image`만 바꾼다. `pull_policy: never` + `localhost/` 접두라서 외부 레지스트리에서 받아오지 않는다.
- **해제 시점**: 업스트림 Dify 1.18 이상(Node ≥ 24.22.1 내장)으로 업그레이드할 때 override 파일과 이 폴더를 지운다. dify-sandbox는 업스트림 main(1b501ff1)이 Node 24.22.1로 올렸지만 이미지 빌드가 실패해 릴리스가 없다. 새 릴리스가 나오면 sandbox 항목도 공식 이미지로 되돌린다.

## 파일

| 파일 | 내용 |
|---|---|
| `api.Dockerfile` | 이미지에 이미 설정된 NodeSource 저장소에서 `nodejs=24.22.2-1nodesource1`로 교체 |
| `web.Dockerfile` | `node:24.22.2-alpine`의 node 바이너리 복사 + 빌드 시 실행 확인(musl 호환) |
| `local-sandbox.Dockerfile` | nodejs.org 배포본 + SHASUMS256 검증 → `/usr/local` 교체(전역 pnpm 유지) |
| `sandbox.Dockerfile` | 기동 시 풀리는 Node tarball 교체 + 구 v20 tarball 삭제 + `NODE_TAR_XZ`·`NODE_DIR` 갱신 |
| `build.sh` | 4종 빌드(서버에 있는 공식 베이스 이미지 사용, 컨테이너 무변경) |
| `verify.sh <프로젝트>` | 실행 중인 6개 서비스의 Node ≥ 24.22.1·상태·이미지, sandbox `/opt` v20 잔존 확인(읽기 전용) |

## 운영 적용 (운영 서버 · 사용자 실행 · 대화형 터미널)

전제: compose 프로젝트 `docker`, 경로 `/app/dify/docker`. AskON이 `docker_default`에 외부 합류해 있으므로 **`down` 금지** — 대상 서비스만 `up -d`로 재생성한다. DB 스키마 변경이 없어 콜드 tar는 필요 없다. 롤백은 공식 이미지로 되돌리는 것이다.

```bash
# ⓪ 스코프·현재 상태 기록
cd /app/dify/docker && pwd && git -C /app/dify status --short && git -C /app/dify log -1 --oneline
docker compose -p docker ps --format '{{.Service}}\t{{.Image}}\t{{.Status}}' | tee ~/nd-dify-before-$(date +%Y%m%d_%H%M%S).txt
docker compose -p docker ps -q api_websocket   # 출력이 있으면(collaboration 프로필 기동 중) ④·롤백의 서비스 목록에 api_websocket 을 추가하고, verify.sh 를 EXPECT_WEBSOCKET=1 로 실행한다
ls -la docker-compose.override.* 2>/dev/null   # 기존 override 가 있으면 중단하고 병합 방법을 먼저 정한다
docker network inspect docker_default --format '{{range .Containers}}{{.Name}} {{end}}' | tr ' ' '\n' | grep -v '^docker-' | sort

# ① 롤백용 공식 이미지가 로컬에 있는지 확인(지우지 않는다)
docker image inspect --format '{{index .RepoDigests 0}}' \
  langgenius/dify-api:1.17.1 langgenius/dify-web:1.17.1 \
  langgenius/dify-agent-local-sandbox:1.17.1 langgenius/dify-sandbox:0.2.15

# ② 브랜치 반영 — git switch 금지(volumes 심볼릭 함정). deploy-1.17.1 에서 fast-forward 만
git -C /app/dify fetch origin deploy-1.17.1 && git -C /app/dify merge --ff-only FETCH_HEAD
ls -la volumes   # 심볼릭(→ /data/dify-volumes) 유지 확인

# ③ 빌드(컨테이너 무변경, 수 분)
bash dgist-node-patch/build.sh

# ④ 적용 — 대상 서비스만 재생성(다운타임 1~3분)
docker compose -p docker config --images | sort -u        # localhost/dgist/* 7건이 보여야 함
docker compose -p docker up -d api worker worker_beat web local_sandbox sandbox

# ⑤ 검증
bash dgist-node-patch/verify.sh docker                     # 전부 OK, exit 0 (이미지·running·healthy·Node ≥ 24.22.1·sandbox v20 잔존 0. healthy 까지 최대 180초 대기)
docker network inspect docker_default --format '{{range .Containers}}{{.Name}} {{end}}' | tr ' ' '\n' | grep -v '^docker-' | sort   # ⓪과 같아야 함(askon 포함)
docker compose -p docker logs --since 5m api worker web sandbox local_sandbox 2>&1 | grep -i -c -E 'error|traceback'   # 기동 직후 값 기록
# 육안: 챗봇 4종 각 1회 응답(코드 노드·지식 검색 경로) · Dify 콘솔 로그인 1회
```

## 롤백 (이미지만 — DB·볼륨 무관)

```bash
cd /app/dify/docker
mv docker-compose.override.yaml ~/docker-compose.override.yaml.disabled   # 추적 파일 → git status 가 더러워진다. 복귀 후 정식으로 git revert 처리
docker compose -p docker up -d api worker worker_beat web local_sandbox sandbox
bash dgist-node-patch/verify.sh docker official           # 공식 이미지·running·healthy 확인
# 다시 적용: mv ~/docker-compose.override.yaml.disabled docker-compose.override.yaml && 같은 up -d
```

## 유의

- `docker compose pull`은 override 대상 서비스를 건너뛴다(`pull_policy: never`). 빌드 전에 `up`을 하면 "No such image"로 멈춘다. 이것은 의도된 안전 실패다.
- 오버레이 이미지 태그는 서버 로컬에만 있다. `docker image prune -a`류로 지우면 재기동이 실패한다 — `build.sh`로 다시 빌드하면 된다.
- dev 서버(프로젝트 `dify`)에서 같은 절차로 먼저 검증했다(2026-10-29). 결과:
  - 빌드 4종 성공. Node v24.22.2이고, local_sandbox는 npm 11.19.1·pnpm 11.9.0을 유지했다.
  - `verify.sh` 7항목 OK.
  - 코드 노드 경로(`CodeExecutor.execute_workflow_code_template`)로 JS(Node 24.22.2, seccomp 아래 Brotli 왕복)·Python 3.14.4·Jinja2를 각 1회 실행해 모두 성공했다.
  - 서비스 API chat-messages 200(지식 검색 앱).
  - 롤백 리허설: 공식 이미지 복귀 14초, `verify.sh dify official` OK, 재적용 OK.
  - 상세 기록은 볼트 「Node.js 2026-10 보안 패치 계획」 §4-4에 남긴다.
- dev·운영 서버에 이 파일들을 브랜치 반영 전에 손으로 복사해 두었다면, `git merge` 전에 지워야 한다. 남겨 두면 "untracked working tree files would be overwritten"으로 멈춘다.
