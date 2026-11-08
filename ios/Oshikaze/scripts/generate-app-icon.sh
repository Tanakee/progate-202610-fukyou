#!/bin/zsh
set -euo pipefail

# imagegen で作った原画から、App Store 用の 1024px アイコンを作り直す。
# 原画を差し替えたときは、このスクリプトを実行するだけでアセットを更新できる。
script_dir="${0:A:h}"
source_image="$script_dir/AppIcon-master.png"
output_image="$script_dir/../Oshikaze/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

sips --resampleHeightWidth 1024 1024 "$source_image" --out "$output_image"
