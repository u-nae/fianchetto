#!/usr/bin/env bash
# Tart 가상 머신 안에서 scripts/capture-readme-screenshots.sh를 실행하고 PNG를 가져온다(docs/images/CAPTURE.md).
# 호스트에서 UI 테스트 자동화 모드가 켜지지 않거나 호스트 키보드를 계속 쓰고 싶을 때 쓴다. 접속 방식은 vm-verify.sh(0029)와 같다.
# 사용법: scripts/vm-capture-readme-screenshots.sh [출력 폴더]   (기본값 docs/images)
set -euo pipefail

cd "$(dirname "$0")/.."
OUTPUT="${1:-docs/images}"
VM="${FIANCHETTO_VM:-fianchetto-ui}"
KEY="${FIANCHETTO_VM_KEY:-$HOME/.ssh/tart_fianchetto}"
VM_USER="${FIANCHETTO_VM_USER:-admin}"
REMOTE="fianchetto"
LOGS="build/logs/vm"
mkdir -p "$OUTPUT" "$LOGS"

command -v tart >/dev/null || { echo "FAIL: tart가 설치되어 있지 않다" >&2; exit 1; }
[[ -f "$KEY" ]] || { echo "FAIL: SSH 키가 없다: $KEY" >&2; exit 1; }
tart list --quiet | grep -qx "$VM" || { echo "FAIL: 가상 머신 '$VM'이 없다" >&2; exit 1; }

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

vm "rm -rf ~/$REMOTE.next && mkdir ~/$REMOTE.next"
git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' file; do if [[ -e "$file" ]]; then printf '%s\0' "$file"; fi; done |
  tar --no-mac-metadata --null -T - -cf - | vm "tar -xf - -C ~/$REMOTE.next"
vm "rm -rf ~/$REMOTE && mv ~/$REMOTE.next ~/$REMOTE"

vm "pkill -x Fianchetto || true"
# 알림 배너(Tips 등)가 창 위에 찍히지 않도록 떠 있는 배너를 치운다. 알림 센터는 바로 다시 뜬다.
vm "killall NotificationCenter >/dev/null 2>&1 || true"
status=0
vm "cd ~/$REMOTE && FIANCHETTO_DERIVED_DATA=\$HOME/DerivedData/Fianchetto-verify scripts/capture-readme-screenshots.sh build/readme-shots" ||
  status=$?
vm "tar -cf - -C ~/$REMOTE/build/logs ." | tar -xf - -C "$LOGS" || true
if ((status != 0)); then
  echo "FAIL: 가상 머신 캡처 실패 (로그: $LOGS/capture-readme.log)" >&2
  exit "$status"
fi
vm "tar -cf - -C ~/$REMOTE/build/readme-shots ." | tar -xf - -C "$OUTPUT"
echo "OK: $OUTPUT"
ls -1 "$OUTPUT"/*.png
