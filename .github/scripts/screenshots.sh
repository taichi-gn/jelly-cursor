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
swiftc -O .github/scripts/press-key.swift -o "$TOOLS/press-key"
swiftc -O .github/scripts/click.swift -o "$TOOLS/click"

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

# 設定画面をクリックしてから ⌘W で閉じたら、窓が消えて、前面が開く前のアプリに戻ること（イベントを送れるときだけ）。
# 起動しただけでは前面になれない（macOS 14 からは、ユーザーの操作なしに前面を取れない）ので、実際の使い方と同じくクリックする
before=$("$TOOLS/diagnose" JellyCursor | grep frontmost)
echo "開く前: $before"
launch -OpenSettings general
IFS=, read -r wx wy ww wh <<<"$("$TOOLS/window-bounds" JellyCursor)"
if "$TOOLS/click" $((wx + ww / 2)) $((wy + 12)); then
    sleep 1
    echo "クリックしたあと: $("$TOOLS/diagnose" JellyCursor | grep frontmost)"
    "$TOOLS/press-key" 13 command
    sleep 1
    after=$("$TOOLS/diagnose" JellyCursor | grep frontmost)
    echo "閉じたあと: $after"
    if "$TOOLS/window-bounds" JellyCursor 2>/dev/null; then
        echo "⌘W で設定画面が閉じなかった"
        exit 1
    fi
    if [ "$after" = "frontmost: JellyCursor" ]; then
        echo "設定画面を閉じても JellyCursor が前面に残った"
        exit 1
    fi
    echo "⌘W で設定画面が閉じ、前面が戻った"
else
    echo "イベントを送る許可が無いので、⌘W の確認は飛ばした"
fi
quit

# 円を描いて速く動かしている間と、止めた直後（戻る揺れ）の矢印。
# CI の Mac は「視差効果を減らす」がオンで、初期設定では止まるので、その設定だけ外して撮る
settings='{"pauseWhenReduceMotion": false, "pauseOnLowPower": false}'
defaults write local.jellycursor settings -data "$(printf '%s' "$settings" | xxd -p | tr -d '\n')"
launch
# 描いている間は、本物のカーソルが隠れていること
"$TOOLS/diagnose" JellyCursor | tee "$TOOLS/drawing.txt"
if ! grep -q "cursor visible: false" "$TOOLS/drawing.txt"; then
    echo "描いている間も本物のカーソルが見えている"
    exit 1
fi
"$TOOLS/move-mouse" 600 400 150 2.0 &
mover=$!
sleep 1.2
screencapture -x -R"380,180,440,440" "$OUT/moving.png"
wait "$mover"
sleep 0.12
screencapture -x -R"380,180,440,440" "$OUT/stopping.png"
"$TOOLS/diagnose" JellyCursor
quit

# ショートカット（⌃⌥⌘J）でオフにすると本物のカーソルが見えて描く窓が消え、もう一度押すと戻ること。
# キー入力を送る許可が無い Mac では確かめられないので飛ばす
settings='{"pauseWhenReduceMotion": false, "pauseOnLowPower": false, "shortcut": {"keyCode": 38, "modifiers": 11, "keyLabel": "J"}}'
defaults write local.jellycursor settings -data "$(printf '%s' "$settings" | xxd -p | tr -d '\n')"
launch
"$TOOLS/diagnose" JellyCursor
set +e
"$TOOLS/press-key" 38 control,option,command
pressed=$?
set -e
if [ "$pressed" -eq 0 ]; then
    sleep 1
    "$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-shortcut.txt"
    if ! grep -q "cursor visible: true" "$TOOLS/after-shortcut.txt" || grep -q "layer=2147483630" "$TOOLS/after-shortcut.txt"; then
        echo "ショートカットでオフにならなかった"
        exit 1
    fi
    "$TOOLS/press-key" 38 control,option,command
    sleep 1
    "$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-shortcut-again.txt"
    if ! grep -q "layer=2147483630" "$TOOLS/after-shortcut-again.txt"; then
        echo "ショートカットでオンに戻らなかった"
        exit 1
    fi
    echo "ショートカットの確認: 通過"
else
    echo "キー入力を送る許可が無いので、ショートカットの確認は飛ばした"
fi
quit

# killall（SIGTERM）で終わらせたあとは、本物のカーソルが見えていること。
# プロセスが終われば macOS も戻すので、終わり方の全体を確かめるもので、シグナルの受け取り方だけを確かめるものではない
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
