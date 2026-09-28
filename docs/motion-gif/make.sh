#!/bin/bash
# README の動きの GIF（docs/images/motion.gif）を作り直す。リポジトリの一番上で実行する。
# JellyCursorCore の動きの計算をそのまま使って頂点を出し（main.swift）、Pillow で絵にする（render.py。pip install pillow）
set -euo pipefail
mkdir -p .build
swiftc -O -package-name JellyCursor Sources/JellyCursorCore/*.swift docs/motion-gif/main.swift -o .build/motion-frames
.build/motion-frames .build/motion-frames.json
python3 docs/motion-gif/render.py .build/motion-frames.json docs/images/motion.gif
