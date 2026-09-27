#!/bin/bash
# CI の macOS で JellyCursor を実際に起動し、設定画面の各タブと、マウスを動かしている間・止めた直後のカーソルを撮る。
# 起動してすぐ落ちないことも確かめる
set -euo pipefail
OUT="$PWD/screenshots"
APP="$PWD/JellyCursor.app"
TOOLS="$PWD/.build/ci-tools"
mkdir -p "$OUT" "$TOOLS"
swiftc -O .github/scripts/window-bounds.swift -o "$TOOLS/window-bounds"
swiftc -O .github/scripts/move-mouse.swift -o "$TOOLS/move-mouse"
swiftc -O .github/scripts/diagnose.swift -o "$TOOLS/diagnose"

launch() {
    open -n "$APP" --args "$@"
    sleep 5
    if ! pgrep -x JellyCursor >/dev/null; then
        echo "JellyCursor が起動後に終わってしまった"
        ls -la ~/Library/Logs/DiagnosticReports 2>/dev/null || true
        exit 1
    fi
}

quit() {
    pkill -x JellyCursor || true
    sleep 1
}

# 設定は初期状態から始める
defaults delete local.jellycursor 2>/dev/null || true

for tab in general motion cursors autoPause about; do
    launch -OpenSettings "$tab"
    bounds=$("$TOOLS/window-bounds" JellyCursor)
    echo "settings-$tab: $bounds"
    screencapture -x -R"$bounds" "$OUT/settings-$tab.png"
    quit
done

# 円を描いて速く動かしている間と、止めた直後（戻る揺れ）の矢印。
# CI の Mac は「視差効果を減らす」がオンで、初期設定では止まるので、その設定だけ外して撮る
settings='{"pauseWhenReduceMotion": false, "pauseOnLowPower": false}'
defaults write local.jellycursor settings -data "$(printf '%s' "$settings" | xxd -p | tr -d '\n')"
launch
"$TOOLS/diagnose" JellyCursor
"$TOOLS/move-mouse" 600 400 150 2.0 &
mover=$!
sleep 1.2
screencapture -x -R"380,180,440,440" "$OUT/moving.png"
wait "$mover"
sleep 0.12
screencapture -x -R"380,180,440,440" "$OUT/stopping.png"
"$TOOLS/diagnose" JellyCursor
quit

# killall（SIGTERM）で終わらせたあとは、本物のカーソルが見えていること
"$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-quit.txt"
if ! grep -q "cursor visible: true" "$TOOLS/after-quit.txt"; then
    echo "終了したあとも本物のカーソルが見えていない"
    exit 1
fi

if ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i jellycursor; then
    echo "クラッシュの記録がある"
    exit 1
fi
ls -la "$OUT"

# 成果物を取り出せない環境でも見られるよう、縮めた JPEG を base64 でログにも出す
for png in "$OUT"/*.png; do
    jpg="${png%.png}.jpg"
    sips -s format jpeg -s formatOptions 70 "$png" --out "$jpg" >/dev/null
    echo "BEGIN-IMAGE $(basename "$jpg")"
    base64 -b 100 -i "$jpg"
    echo "END-IMAGE"
done
