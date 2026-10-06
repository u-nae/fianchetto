#!/usr/bin/env bash
# 0028: 스냅샷 테스트가 앱 컨테이너 임시 폴더에 새로 기록한 기준 이미지를 저장소로 옮긴다.
# 단위 테스트 호스트 앱이 샌드박스라 테스트가 저장소에 직접 쓰지 못하기 때문이다.
# 사용법: 스냅샷 테스트를 한 번 돌려(기준 이미지가 없으면 실패하며 기록한다) 이 스크립트를 실행하고, 이미지를 확인한 뒤 커밋한다.
# 기준 이미지가 바뀌는 PR은 디자인 세션이 이미지를 보고 확인한다.
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$HOME/Library/Containers/io.github.u-nae.Fianchetto/Data/tmp/FianchettoSnapshots"
DEST="FianchettoTests/Snapshots/References"

if [[ ! -d "$WORK" ]]; then
  echo "기록된 스냅샷이 없다: $WORK" >&2
  exit 1
fi
mkdir -p "$DEST"
count=0
while IFS= read -r -d '' file; do
  name=$(basename "$file")
  if [[ ! -f "$DEST/$name" ]] || ! cmp -s "$file" "$DEST/$name"; then
    cp "$file" "$DEST/$name"
    echo "기록: $DEST/$name"
    count=$((count + 1))
  fi
done < <(find "$WORK" -name '*.png' -print0)
echo "새로 옮긴 기준 이미지 ${count}개"
