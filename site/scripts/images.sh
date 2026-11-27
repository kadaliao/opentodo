#!/bin/bash
# 重新生成网站用的截图：用演示数据截 Mac 和 iPhone 的界面（apple/scripts/shot.sh），
# 转成 WebP 放进 site/img/。
#
#   site/scripts/images.sh              # 截图并转换（Mac、iPhone、图标）
#   site/scripts/images.sh mac          # 只截 Mac 的
#   site/scripts/images.sh ios          # 只截 iPhone 的
#   site/scripts/images.sh convert      # 不截图，只把 apple/.shots/site/ 里已有的 PNG 转一遍
#   site/scripts/images.sh mac work-dark board-dark   # 只截列出的几张（名字见下面的表）
#
# 网页跟着系统的深色模式换图：浅色截图都配一张同名 -dark 的，页面里用 <picture> 按外观挑。
#
# 分享预览图 og.jpg 由 site/scripts/og.html 用无头 Chrome 截出来，最后一步生成。
#
# Mac 截图要在有“屏幕录制”权限的本机终端里跑，屏幕不能锁着（docs/apple.md 第 5 节）；
# 经 ssh 登进来的会话没有这个权限，截出来是空白的。iPhone 用模拟器截，不受这些限制。
# 需要 cwebp 和 ImageMagick（brew install webp imagemagick）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHOTS="$ROOT/apple/.shots/site"
IMG="$ROOT/site/img"
SIM="${OT_SITE_SIM:-iPhone Air}"
mkdir -p "$SHOTS" "$IMG"

# 名字 路由 [环境变量…]
MAC_SHOTS=(
  "detail-light|task:report"
  "detail-dark|task:report|OT_APPEARANCE=dark"
  "cal-week-dark|calendar-demo:week|OT_APPEARANCE=dark"
  "work-light|list:work"
  "board-light|board:manual"
  "timeline-light|timeline:week"
  "focus-light|focus"
  "habits-light|habits"
  "countdowns-light|countdowns"
  "matrix-light|matrix"
  "work-dark|list:work|OT_APPEARANCE=dark"
  "board-dark|board:manual|OT_APPEARANCE=dark"
  "timeline-dark|timeline:week|OT_APPEARANCE=dark"
  "focus-dark|focus|OT_APPEARANCE=dark"
  "habits-dark|habits|OT_APPEARANCE=dark"
  "countdowns-dark|countdowns|OT_APPEARANCE=dark"
  "matrix-dark|matrix|OT_APPEARANCE=dark"
  "quick-dark|system:quickpanel|OT_APPEARANCE=dark|OT_QUICKADD=明天下午3点开会 #工作 !高"
)
IOS_SHOTS=(
  "iphone-today|smart:today"
  "iphone-cal|calendar-demo:month"
  "iphone-habits|habits"
  "iphone-today-dark|smart:today|OT_APPEARANCE=dark"
  "iphone-cal-dark|calendar-demo:month|OT_APPEARANCE=dark"
  "iphone-habits-dark|habits|OT_APPEARANCE=dark"
)
ONLY=("${@:2}")  # 命令行上第一个参数之后的名字：只截这几张

wanted() { # name
  [ ${#ONLY[@]} -eq 0 ] && return 0
  local n; for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

shoot() { # platform entry…
  local platform=$1; shift
  local built=""
  for entry in "$@"; do
    IFS='|' read -r -a f <<<"$entry"
    local name=${f[0]} route=${f[1]} envs=("${f[@]:2}")
    wanted "$name" || continue
    echo "截图 $name ($route)"
    if [ "$platform" = macos ]; then
      env OT_WINDOW_SIZE=1280x800 OT_MAC_METHOD=window ${built:+OT_NO_BUILD=1} ${envs[@]+"${envs[@]}"} \
        "$ROOT/apple/scripts/shot.sh" macos "$route" "$SHOTS/$name.png" >/dev/null || echo "  失败：$name" >&2
    else
      env ${built:+OT_NO_BUILD=1} ${envs[@]+"${envs[@]}"} \
        "$ROOT/apple/scripts/shot.sh" ios "$SIM" "$route" "$SHOTS/$name.png" >/dev/null || echo "  失败：$name" >&2
    fi
    built=1
  done
}

convert_all() {
  local png name
  for png in "$SHOTS"/*.png; do
    [ -e "$png" ] || continue
    name="$(basename "$png" .png)"
    case "$name" in
      quick-dark)
        # 只要浮在窗口上的快速添加面板（1280×800 窗口的两倍图里，面板在 1275×127+643+384）
        magick "$png" -crop 1275x127+643+384 +repage "$SHOTS/.tmp.png"
        cwebp -quiet -q 90 "$SHOTS/.tmp.png" -o "$IMG/quick-panel.webp" ;;
      iphone-*)
        # 页面上最宽 300 点，两倍图 640 像素宽就够
        magick "$png" -resize 640x "$SHOTS/.tmp.png"
        cwebp -quiet -q 84 "$SHOTS/.tmp.png" -o "$IMG/$name.webp" ;;
      *)
        # Mac 窗口：带透明圆角，原尺寸一份（2560 宽）、一半一份
        cwebp -quiet -q 82 -alpha_q 100 "$png" -o "$IMG/$name.webp"
        magick "$png" -resize 1280x "$SHOTS/.tmp.png"
        cwebp -quiet -q 84 -alpha_q 100 "$SHOTS/.tmp.png" -o "$IMG/$name-1280.webp" ;;
    esac
    echo "转换 $name"
  done
  rm -f "$SHOTS/.tmp.png"
}

icons() {
  local set="$ROOT/apple/App/Assets.xcassets/AppIcon.appiconset"
  magick "$set/mac-1024.png" -resize 256x256 "$IMG/icon-256.png"
  magick "$set/mac-128.png" -resize 64x64 "$IMG/icon-64.png"
  magick "$set/ios-light.png" -resize 180x180 "$IMG/icon-180.png"
}

# 分享预览图：用无头 Chrome 把 og.html 截成 1200×630
og() {
  local chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" profile
  profile="$(mktemp -d)"
  "$chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --user-data-dir="$profile" \
    --window-size=1200,630 --virtual-time-budget=3000 --screenshot="$SHOTS/og.png" \
    "file://$ROOT/site/scripts/og.html" >/dev/null 2>&1
  rm -rf "$profile"
  magick "$SHOTS/og.png" -quality 86 "$IMG/og.jpg" && rm "$SHOTS/og.png"
  echo "生成 og.jpg"
}

case "${1:-all}" in
  mac) shoot macos "${MAC_SHOTS[@]}"; convert_all; og ;;
  ios) shoot ios "${IOS_SHOTS[@]}"; convert_all ;;
  convert) convert_all; icons; og ;;
  all) shoot macos "${MAC_SHOTS[@]}"; shoot ios "${IOS_SHOTS[@]}"; convert_all; icons; og ;;
  *) echo "用法：$0 [mac|ios|convert]" >&2; exit 2 ;;
esac
