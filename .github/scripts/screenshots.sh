#!/bin/bash
# CI の macOS で JellyCursor を実際に起動して確かめ、画面を撮る。
# - はじめての起動の案内、設定画面の各タブ、メニューバーのメニュー、Dock のアイコン
# - 円を描いて動かしている間と、止めた直後のカーソル
# - 本物のカーソルの出し入れ、ショートカット、⌘W で閉じたあとの前面、止まっている間と動かしている間の CPU
# キー入力やクリックを送る許可が無い Mac では、それを使う確認だけ飛ばす
set -euo pipefail
OUT="$PWD/screenshots"
APP="$PWD/JellyCursor.app"
TOOLS="$PWD/.build/ci-tools"
mkdir -p "$OUT" "$TOOLS"
for tool in window-bounds move-mouse diagnose press-key click; do
    swiftc -O ".github/scripts/$tool.swift" -o "$TOOLS/$tool"
done

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

fail() {
    echo "$1"
    exit 1
}

# 設定を書く（JSON を UserDefaults のデータとして）
write_settings() {
    defaults write local.jellycursor settings -data "$(printf '%s' "$1" | xxd -p | tr -d '\n')"
}

# プロセスがこれまでに使った CPU 時間（秒）
cpu_seconds() {
    ps -o time= -p "$1" | awk -F: '{ if (NF == 3) print $1 * 3600 + $2 * 60 + $3; else print $1 * 60 + $2 }'
}

# はじめての起動では、案内つきで設定画面が開く
defaults delete local.jellycursor 2>/dev/null || true
launch
bounds=$("$TOOLS/window-bounds" JellyCursor) || fail "はじめての起動で設定画面が開かなかった"
screencapture -x -R"$bounds" "$OUT/welcome.png"
# 画面全体も撮る（設定画面を開いている間は、Dock にアイコンが出る）
screencapture -x "$OUT/screen.png"
quit

# ここからは案内を出さない
defaults write local.jellycursor welcomed -bool true
for tab in general motion cursors autoPause about; do
    launch -OpenSettings "$tab"
    bounds=$("$TOOLS/window-bounds" JellyCursor)
    echo "settings-$tab: $bounds"
    screencapture -x -R"$bounds" "$OUT/settings-$tab.png"
    quit
done

# メニューバーのアイコンをクリックしてメニューを開く
launch
if status=$("$TOOLS/window-bounds" JellyCursor 25); then
    IFS=, read -r sx sy sw sh <<<"$status"
    if "$TOOLS/click" $((sx + sw / 2)) $((sy + sh / 2)); then
        sleep 1
        if menu=$("$TOOLS/window-bounds" JellyCursor 101); then
            screencapture -x -R"$menu" "$OUT/menu.png"
            echo "メニュー: $menu"
        else
            echo "メニューが開かなかった"
        fi
        "$TOOLS/press-key" 53 || true
    fi
else
    echo "メニューバーのアイコンが見つからなかった"
fi
quit

# 設定画面をクリックしてから ⌘W で閉じたら、窓が消えて、前面が開く前のアプリに戻ること。
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
        fail "⌘W で設定画面が閉じなかった"
    fi
    [ "$after" != "frontmost: JellyCursor" ] || fail "設定画面を閉じても JellyCursor が前面に残った"
    echo "⌘W で設定画面が閉じ、前面が戻った"
else
    echo "イベントを送る許可が無いので、⌘W の確認は飛ばした"
fi
quit

# 円を描いて速く動かしている間と、止めた直後（戻る揺れ）の矢印。
# CI の Mac は「視差効果を減らす」がオンで、初期設定では止まるので、その設定だけ外して撮る
write_settings '{"pauseWhenReduceMotion": false, "pauseOnLowPower": false}'
launch
# 描いている間は、本物のカーソルが隠れていること
"$TOOLS/diagnose" JellyCursor | tee "$TOOLS/drawing.txt"
grep -q "cursor visible: false" "$TOOLS/drawing.txt" || fail "描いている間も本物のカーソルが見えている"
# 止まっている間の CPU（10秒）
pid=$(pgrep -x JellyCursor)
sleep 2
start=$(cpu_seconds "$pid")
sleep 10
idle=$(awk -v a="$start" -v b="$(cpu_seconds "$pid")" 'BEGIN { printf "%.1f", (b - a) / 10 * 100 }')
echo "止まっている間の CPU: ${idle}%"
"$TOOLS/move-mouse" 600 400 150 2.0 &
mover=$!
sleep 1.2
screencapture -x -R"380,180,440,440" "$OUT/moving.png"
wait "$mover"
sleep 0.12
screencapture -x -R"380,180,440,440" "$OUT/stopping.png"
# 動かしている間の CPU（5秒）
start=$(cpu_seconds "$pid")
"$TOOLS/move-mouse" 500 380 120 5.0
moving=$(awk -v a="$start" -v b="$(cpu_seconds "$pid")" 'BEGIN { printf "%.1f", (b - a) / 5 * 100 }')
echo "動かしている間の CPU: ${moving}%"
"$TOOLS/diagnose" JellyCursor
quit
# 止まっている間に何かが回り続けていないこと（仮想マシンの揺れを見込んで、ゆるく確かめる）
awk -v v="$idle" 'BEGIN { exit !(v < 10) }' || fail "止まっている間の CPU が多すぎる: ${idle}%"

# ショートカット（⌃⌥⌘J）でオフにすると本物のカーソルが見えて描く窓が消え、もう一度押すと戻ること
write_settings '{"pauseWhenReduceMotion": false, "pauseOnLowPower": false, "shortcut": {"keyCode": 38, "modifiers": 11, "keyLabel": "J"}}'
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
        fail "ショートカットでオフにならなかった"
    fi
    "$TOOLS/press-key" 38 control,option,command
    sleep 1
    "$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-shortcut-again.txt"
    grep -q "layer=2147483630" "$TOOLS/after-shortcut-again.txt" || fail "ショートカットでオンに戻らなかった"
    echo "ショートカットの確認: 通過"
else
    echo "キー入力を送る許可が無いので、ショートカットの確認は飛ばした"
fi
quit

# killall（SIGTERM）で終わらせたあとは、本物のカーソルが見えていること。
# プロセスが終われば macOS も戻すので、終わり方の全体を確かめるもので、シグナルの受け取り方だけを確かめるものではない
"$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-quit.txt"
grep -q "cursor visible: true" "$TOOLS/after-quit.txt" || fail "終了したあとも本物のカーソルが見えていない"

if ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i jellycursor; then
    fail "クラッシュの記録がある"
fi
ls -la "$OUT"

# 成果物を取り出せない環境でも見られるよう、画像を base64 でログにも出す
for png in "$OUT"/*.png; do
    echo "BEGIN-IMAGE $(basename "$png")"
    base64 -b 100 -i "$png"
    echo "END-IMAGE"
done
