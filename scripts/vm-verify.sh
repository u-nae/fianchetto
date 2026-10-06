#!/usr/bin/env bash
# 0029: Tart 가상 머신 안에서 scripts/verify.sh를 실행한다. UI 테스트는 가상 머신의 키보드·마우스만 쓰므로
# 검증하는 동안에도 호스트를 그대로 쓸 수 있다.
# 가상 머신은 창을 띄워 실행해야 한다. 화면 없이(--no-graphics) 실행하면 UI 테스트 자동화 모드가 켜지지 않는다.
# 사용법: scripts/vm-verify.sh            (가상 머신에서 전체 검증)
#         SKIP_UI_TESTS=1 scripts/vm-verify.sh
# 환경 변수: FIANCHETTO_VM(기본 fianchetto-ui), FIANCHETTO_VM_KEY(기본 ~/.ssh/tart_fianchetto),
#           FIANCHETTO_VM_USER(기본 admin)
# 가상 머신 준비 절차는 docs/decisions/0029-ui-tests-in-tart-vm.md에 있다.
set -euo pipefail

cd "$(dirname "$0")/.."
VM="${FIANCHETTO_VM:-fianchetto-ui}"
KEY="${FIANCHETTO_VM_KEY:-$HOME/.ssh/tart_fianchetto}"
VM_USER="${FIANCHETTO_VM_USER:-admin}"
REMOTE="fianchetto"
LOGS="build/logs/vm"

command -v tart >/dev/null || { echo "FAIL: tart가 설치되어 있지 않다" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "FAIL: SSH 키가 없다: $KEY" >&2; exit 1; }
if ! tart list --quiet | grep -qx "$VM"; then
  echo "FAIL: 가상 머신 '$VM'이 없다" >&2
  exit 1
fi

running() { tart list --format json | /usr/bin/python3 -I -c '
import json, sys
name = sys.argv[1]
sys.exit(0 if any(vm["Name"] == name and vm["Running"] for vm in json.load(sys.stdin)) else 1)' "$VM"; }

started=0
if ! running; then
  echo "가상 머신 '$VM' 실행(창 표시)"
  nohup tart run "$VM" >/dev/null 2>&1 &
  started=1
fi
stop_vm() { if ((started)); then tart stop "$VM" >/dev/null 2>&1 || true; fi; }
trap stop_vm EXIT

# 가상 머신은 로컬 NAT 주소를 부팅마다 새로 받으므로 호스트 키를 저장하지 않는다.
ssh_opts=(-i "$KEY" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
ip=""
for _ in $(seq 1 60); do
  ip=$(tart ip "$VM" 2>/dev/null || true)
  if [[ -n "$ip" ]] && ssh "${ssh_opts[@]}" -o ConnectTimeout=3 "$VM_USER@$ip" true 2>/dev/null; then
    break
  fi
  ip=""
  sleep 3
done
[[ -n "$ip" ]] || { echo "FAIL: 가상 머신에 SSH로 접속하지 못했다" >&2; exit 1; }
vm() { ssh "${ssh_opts[@]}" "$VM_USER@$ip" "$@"; }
echo "가상 머신 macOS $(vm sw_vers -productVersion), $(vm xcodebuild -version | head -1)"

# 추적 파일과 무시하지 않은 새 파일만 보낸다. 작업 복사본이 매번 저장소와 같아지도록 새 폴더에 받는다.
vm "rm -rf ~/$REMOTE.next && mkdir ~/$REMOTE.next"
git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' file; do if [[ -e "$file" ]]; then printf '%s\0' "$file"; fi; done |
  tar --no-mac-metadata --null -T - -cf - | vm "tar -xf - -C ~/$REMOTE.next"
vm "rm -rf ~/$REMOTE && mv ~/$REMOTE.next ~/$REMOTE"

status=0
vm "cd ~/$REMOTE && SKIP_UI_TESTS=${SKIP_UI_TESTS:-0} FIANCHETTO_DERIVED_DATA=\$HOME/DerivedData/Fianchetto-verify scripts/verify.sh" ||
  status=$?
mkdir -p "$LOGS"
vm "tar -cf - -C ~/$REMOTE/build/logs ." | tar -xf - -C "$LOGS" || true
echo "가상 머신 로그: $LOGS"
if ((status != 0)); then
  echo "FAIL: 가상 머신 검증 실패" >&2
  exit "$status"
fi
echo "OK: 가상 머신 검증 통과 (가상 머신 macOS 기준. macOS 15 실기 실행은 미검증)"
