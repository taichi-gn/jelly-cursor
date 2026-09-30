#!/bin/bash
# CI の macOS で JellyCursor を実際に起動して確かめ、画面を撮る。
# - はじめての起動の案内、設定画面の各タブ、メニューバーのメニュー、Dock のアイコン
# - 円を描いて動かしている間と、止めた直後のカーソル
# - 本物のカーソルの出し入れ、ショートカット、⌘W で閉じたあとの前面、止まっている間と動かしている間の CPU、
#   動きのプレビュー、Dock のアイコン、残る記録、クリックで弾むこと、設定のタブのフォーカスの枠
# キー入力やクリックを送る許可が無い Mac では、それを使う確認だけ飛ばす
set -euo pipefail
OUT="$PWD/screenshots"
APP="$PWD/JellyCursor.app"
TOOLS="$PWD/.build/ci-tools"
SUMMARY="$TOOLS/summary.txt"
mkdir -p "$OUT" "$TOOLS"
: >"$SUMMARY"

# 結果の要点。ログの最後にまとめて出す（画像のあとに出さないと、長いログの取り出しで切れる）
note() {
    echo "$1"
    echo "$1" >>"$SUMMARY"
}
for tool in window-bounds move-mouse diagnose press-key click ax-frame image-stats; do
    swiftc -O ".github/scripts/$tool.swift" -o "$TOOLS/$tool"
done

# 終わるとき（途中で失敗したときも）に、撮った画像と結果の要点を出す。
# 成果物を取り出せない環境でも見られるよう、画像は base64 でログにも出す。画面全体は大きいので縮めた JPEG にする。
# 設定画面の各タブは成果物にだけ入れ、ログには、確かめたい画像だけを出す
report() {
    for name in screen menu-screen; do
        [ -f "$OUT/$name.png" ] || continue
        sips -s format jpeg -s formatOptions 60 --resampleWidth 800 "$OUT/$name.png" --out "$TOOLS/$name.jpg" >/dev/null || true
    done
    for name in settings-about focus-motion focus-general focus-cursors; do
        [ -f "$OUT/$name.png" ] || continue
        sips -s format jpeg -s formatOptions 70 "$OUT/$name.png" --out "$TOOLS/$name.jpg" >/dev/null || true
    done
    for image in "$TOOLS/screen.jpg" "$TOOLS/menu-screen.jpg" "$TOOLS"/preview-1.png "$OUT"/settings-motion.png "$TOOLS"/focus-motion.jpg "$OUT"/menu.png "$OUT"/moving.png "$OUT"/stopping.png "$OUT"/click-rest.png "$OUT"/click-pressed.png "$OUT"/click-released.png; do
        [ -f "$image" ] || continue
        echo "BEGIN-IMAGE $(basename "$image")"
        base64 -b 100 -i "$image"
        echo "END-IMAGE"
    done
    echo "===== まとめ ====="
    cat "$SUMMARY"
}
trap report EXIT

launch() {
    open -n "$APP" --args "$@"
    sleep 5
    if ! pgrep -x JellyCursor >/dev/null; then
        ls -la ~/Library/Logs/DiagnosticReports 2>/dev/null || true
        fail "JellyCursor が起動後に終わってしまった"
    fi
}

quit() {
    pkill -x JellyCursor || true
    sleep 1
}

fail() {
    note "失敗: $1"
    exit 1
}

# 画面の部品の範囲をアクセシビリティの API で探す（ax-frame <バンドル ID> <名前>）。
# 中身を読めなかったとき（3）は、忙しいだけのことがあるので少し待って3回まで試す
ax_frame() {
    local status=1
    for _ in 1 2 3; do
        if "$TOOLS/ax-frame" "$@"; then return 0; else status=$?; fi
        [ "$status" -eq 3 ] || return "$status"
        sleep 1
    done
    return "$status"
}

# .app に入れたアイコン
note "Resources: $(ls "$APP/Contents/Resources" | tr '\n' ' ')"
note "Info.plist のアイコン: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" 2>&1)"
sips -s format png -Z 256 "$APP/Contents/Resources/AppIcon.icns" --out "$OUT/icon.png" >/dev/null 2>&1 || note "AppIcon.icns を読めない"

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
# 設定画面を開いている間は Dock にアイコンが出る。空のアイコンになっていないこと
screencapture -x "$OUT/screen.png"
note "設定画面を開いたあと: $("$TOOLS/diagnose" JellyCursor | grep "regular apps")"
set +e
tile=$(ax_frame com.apple.dock JellyCursor)
found=$?
set -e
if [ "$found" -eq 0 ]; then
    screencapture -x -R"$tile" "$OUT/dock-tile.png"
    # 範囲には Dock の背景も入るので、真ん中だけを見る。空のアイコンは灰色で、色の付いた点がほとんど無い
    IFS=, read -r tx ty tw th <<<"$tile"
    screencapture -x -R"$((tx + tw / 4)),$((ty + th / 4)),$((tw / 2)),$((th / 2))" "$TOOLS/dock-tile-center.png"
    stats=$("$TOOLS/image-stats" "$TOOLS/dock-tile-center.png")
    note "Dock のアイコン: $tile $stats"
    colorful=$(sed -E 's/.*colorful=([0-9.]+).*/\1/' <<<"$stats")
    awk -v v="$colorful" 'BEGIN { exit !(v >= 0.3) }' || fail "Dock のアイコンが色の無い（空の）アイコンになっている"
elif [ "$found" -eq 2 ]; then
    note "アクセシビリティの許可が無いので、Dock のアイコンの確認は飛ばした"
elif [ "$found" -eq 3 ]; then
    note "Dock の中身を読めなかったので、Dock のアイコンの確認は飛ばした"
else
    fail "設定画面を開いても Dock にアイコンが出ていない"
fi
quit

# ここからは案内を出さない
defaults write local.jellycursor welcomed -bool true
for tab in general motion cursors autoPause about; do
    launch -OpenSettings "$tab"
    bounds=$("$TOOLS/window-bounds" JellyCursor)
    note "settings-$tab: $bounds"
    screencapture -x -R"$bounds" "$OUT/settings-$tab.png"
    if [ "$tab" = motion ]; then
        # プレビューに矢印と I 字が描かれていて、動いていること。
        # プレビューは道筋の途中で1秒近く止まって見えることがあるので、それより長くあけて3回撮り、どこかで変わっていればよい
        set +e
        preview=$(ax_frame local.jellycursor "動きのプレビュー")
        found=$?
        set -e
        case "$found" in
            0) note "プレビューの範囲: $preview" ;;
            2 | 3) note "アクセシビリティで読めないので、プレビューの確認は飛ばした"; preview="" ;;
            *) fail "動きのプレビューが見つからない" ;;
        esac
        checksums=""
        for shot in ${preview:+1 2 3}; do
            [ "$shot" -eq 1 ] || sleep 1.2
            screencapture -x -R"$preview" "$TOOLS/preview-$shot.png"
            stats=$("$TOOLS/image-stats" "$TOOLS/preview-$shot.png")
            note "プレビュー $shot: $stats"
            dark=$(sed -E 's/.*dark=([0-9.]+).*/\1/' <<<"$stats")
            awk -v v="$dark" 'BEGIN { exit !(v >= 0.001) }' || fail "動きのプレビューに何も描かれていない"
            checksums="$checksums ${stats##*checksum=}"
        done
        different=$(printf '%s\n' $checksums | sort -u | wc -l | tr -d ' ')
        [ -z "$preview" ] || [ "$different" -gt 1 ] || fail "動きのプレビューが止まっている"
    fi
    quit
done

# タブを切り替えたあとの画面を撮る（キーボード操作用の青い枠（フォーカスの枠）が出ていないかを、画像で見る）。
# 枠はシステム設定の「キーボードナビゲーション」がオンのときに出るので、その設定にして撮り、あとで元に戻す。
# 枠は薄い色で、画像の数値だけでは確かめにくいので、ここは撮るだけにしている
keyboard_ui=$(defaults read NSGlobalDomain AppleKeyboardUIMode 2>/dev/null || true)
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
launch -OpenSettings general
bounds=$("$TOOLS/window-bounds" JellyCursor) || fail "設定画面が開かなかった"
IFS=, read -r wx wy ww wh <<<"$bounds"
if "$TOOLS/click" $((wx + ww / 2)) $((wy + 12)); then
    sleep 0.5
    for tab in "motion 193" "general 143" "cursors 254"; do
        read -r name x <<<"$tab"
        "$TOOLS/click" $((wx + x)) $((wy + 43))
        sleep 1.2
        screencapture -x -R"$wx,$wy,$ww,$wh" "$OUT/focus-$name.png"
        note "タブ $name を選んだあと: $("$TOOLS/image-stats" "$OUT/focus-$name.png")"
    done
else
    note "クリックを送る許可が無いので、フォーカスの枠の確認は飛ばした"
fi
quit
if [ -n "$keyboard_ui" ]; then
    defaults write NSGlobalDomain AppleKeyboardUIMode -int "$keyboard_ui"
else
    defaults delete NSGlobalDomain AppleKeyboardUIMode
fi

# メニューバーのメニューを開いて撮る。macOS 26 ではメニューバーのアイコンが窓の一覧に出ず、
# クリックする場所が分からないので、起動時の指定でアプリに開かせる。
# README に使うので、「視差効果を減らす」で止めずに、動いているときのメニューにする。
write_settings '{"pauseWhenReduceMotion": false, "pauseOnLowPower": false}'
open -a Finder
sleep 1
launch -OpenMenu YES
sleep 1
"$TOOLS/diagnose" JellyCursor | grep "window layer" || true
if menu=$("$TOOLS/window-bounds" JellyCursor 101); then
    screencapture -x -R"$menu" "$OUT/menu.png"
    note "メニュー: $menu"
else
    screencapture -x "$OUT/menu-screen.png"
    note "メニューの窓が見つからなかったので、画面全体を撮った"
fi
"$TOOLS/press-key" 53 || true
quit

# 設定画面をクリックしてから ⌘W で閉じたら、窓が消えて、前面が開く前のアプリに戻ること。
# 起動しただけでは前面になれない（macOS 14 からは、ユーザーの操作なしに前面を取れない）ので、実際の使い方と同じくクリックする。
# 動きのタブで開き、閉じたあとはプレビューが止まって CPU を使わないことも見る
before=$("$TOOLS/diagnose" JellyCursor | grep frontmost)
note "開く前: $before"
launch -OpenSettings motion
pid=$(pgrep -x JellyCursor)
bounds=$("$TOOLS/window-bounds" JellyCursor) || fail "設定画面が開かなかった"
IFS=, read -r wx wy ww wh <<<"$bounds"
if "$TOOLS/click" $((wx + ww / 2)) $((wy + 12)); then
    sleep 1
    note "クリックしたあと: $("$TOOLS/diagnose" JellyCursor | grep frontmost)"
    start=$(cpu_seconds "$pid")
    sleep 5
    note "プレビューを出している間の CPU: $(awk -v a="$start" -v b="$(cpu_seconds "$pid")" 'BEGIN { printf "%.1f", (b - a) / 5 * 100 }')%"
    "$TOOLS/press-key" 13 command
    sleep 1
    after=$("$TOOLS/diagnose" JellyCursor | grep frontmost)
    note "閉じたあと: $after"
    if "$TOOLS/window-bounds" JellyCursor 2>/dev/null; then
        fail "⌘W で設定画面が閉じなかった"
    fi
    [ "$after" != "frontmost: JellyCursor" ] || fail "設定画面を閉じても JellyCursor が前面に残った"
    note "⌘W で設定画面が閉じ、前面が戻った"
    start=$(cpu_seconds "$pid")
    sleep 5
    closed=$(awk -v a="$start" -v b="$(cpu_seconds "$pid")" 'BEGIN { printf "%.1f", (b - a) / 5 * 100 }')
    note "閉じたあとの CPU: ${closed}%"
    awk -v v="$closed" 'BEGIN { exit !(v < 10) }' || fail "設定画面を閉じたあとの CPU が多すぎる: ${closed}%"
else
    note "イベントを送る許可が無いので、⌘W の確認は飛ばした"
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
note "止まっている間の CPU: ${idle}%"
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
note "動かしている間の CPU: ${moving}%"
"$TOOLS/diagnose" JellyCursor
# クリックで弾むこと。押している間は矢印がクリック位置へ向けてつぶれて短くなり、離して落ち着くと元の大きさに戻る。
# Finder の窓より下の黒い机の上で押し、矢印の白い縁を囲む四角の高さを比べる
# （矢印は右下へのびているので、つぶれると高さが縮む。横には少し太るので、対角線より高さのほうが差が大きい）
cx=600; cy=600
region="$((cx - 8)),$((cy - 8)),48,48"
if "$TOOLS/click" "$cx" "$cy"; then
    sleep 1.5
    screencapture -x -R"$region" "$OUT/click-rest.png"
    "$TOOLS/click" "$cx" "$cy" 1.2 &
    clicker=$!
    sleep 0.6
    screencapture -x -R"$region" "$OUT/click-pressed.png"
    wait "$clicker"
    sleep 1.5
    screencapture -x -R"$region" "$OUT/click-released.png"
    box() {
        "$TOOLS/image-stats" "$1" | sed -E 's/.*light-box=([0-9]+x[0-9]+).*/\1/'
    }
    rest=$(box "$OUT/click-rest.png")
    pressed=$(box "$OUT/click-pressed.png")
    released=$(box "$OUT/click-released.png")
    note "クリック: 押す前 ${rest} / 押している間 ${pressed} / 離したあと ${released}（矢印を囲む四角の幅x高さ px）"
    awk -v p="${pressed#*x}" -v r="${rest#*x}" 'BEGIN { exit !(r > 5 && p < r * 0.93) }' || fail "押しても矢印がつぶれていない"
    [ "$released" = "$rest" ] || fail "離したあと元の大きさに戻っていない"
else
    note "クリックを送る許可が無いので、クリックの確認は飛ばした"
fi
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
    note "ショートカットの確認: 通過"
else
    note "キー入力を送る許可が無いので、ショートカットの確認は飛ばした"
fi
quit

# killall（SIGTERM）で終わらせたあとは、本物のカーソルが見えていること。
# プロセスが終われば macOS も戻すので、終わり方の全体を確かめるもので、シグナルの受け取り方だけを確かめるものではない
"$TOOLS/diagnose" JellyCursor | tee "$TOOLS/after-quit.txt"
grep -q "cursor visible: true" "$TOOLS/after-quit.txt" || fail "終了したあとも本物のカーソルが見えていない"
note "終了したあとは本物のカーソルが見えている"

# Finder などが使う .app のアイコン（起動してしばらくたってから）
note "$("$TOOLS/diagnose" JellyCursor "$APP" | grep "bundle icon" || echo "bundle icon: 読めない")"

# 起動や状態の変化の記録が残っていて、あとから log show で見られること
log show --last 15m --style compact --predicate 'subsystem == "local.jellycursor"' >"$TOOLS/log.txt" 2>&1 || true
entries=$(grep -c "local.jellycursor" "$TOOLS/log.txt" || true)
note "残っている記録: ${entries} 件"
{ grep "local.jellycursor" "$TOOLS/log.txt" || true; } | tail -4 | while read -r line; do note "  $line"; done
[ "$entries" -gt 0 ] || fail "記録が残っていない"

if ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i jellycursor; then
    fail "クラッシュの記録がある"
fi
ls -la "$OUT"
