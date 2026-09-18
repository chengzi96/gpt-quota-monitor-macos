#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dist_dir="$project_root/dist"
app_dir="$dist_dir/GPT流量监控.app"
contents_dir="$app_dir/Contents"
component_archive="$project_root/vendor/codex-app-server-aarch64-apple-darwin-0.151.0.tar.gz"
component_archive_sha256="09193ef452f35d3558ac5bef21e14d6e3c9763edaa36e6c614126a15fca0ff57"
component_archive_binary="codex-app-server-aarch64-apple-darwin"
component_resource_name="codex-app-server"
generated_assets="$dist_dir/generated-assets"
icon_source="$generated_assets/AppIcon-1024.png"
menu_icon_source="$generated_assets/MenuBarHourglassTemplate.png"
iconset_dir="$dist_dir/AppIcon.iconset"

cd "$project_root"
/bin/chmod +x scripts/ensure-codex-app-server.sh
./scripts/ensure-codex-app-server.sh

mkdir -p "$dist_dir"
/bin/rm -rf "$generated_assets"
mkdir -p "$generated_assets"
/usr/bin/xcrun swift "$project_root/scripts/generate-assets.swift" "$generated_assets"

swift build -c release

binary_path="$project_root/.build/release/AIQuotaBar"
if [[ ! -x "$binary_path" ]]; then
  echo "未找到编译产物：$binary_path" >&2
  exit 1
fi

if [[ ! -f "$component_archive" ]]; then
  echo "缺少 OpenAI App Server 额度组件：$component_archive" >&2
  exit 1
fi

actual_component_sha256="$(/usr/bin/shasum -a 256 "$component_archive" | /usr/bin/awk '{print $1}')"
if [[ "$actual_component_sha256" != "$component_archive_sha256" ]]; then
  echo "OpenAI App Server 额度组件校验失败。" >&2
  echo "expected: $component_archive_sha256" >&2
  echo "actual:   $actual_component_sha256" >&2
  exit 1
fi

if [[ ! -f "$icon_source" || ! -f "$menu_icon_source" ]]; then
  echo "图标资源生成失败。" >&2
  exit 1
fi

extract_dir="$(/usr/bin/mktemp -d "$dist_dir/.appserver-extract.XXXXXX")"
cleanup() {
  /bin/rm -rf "$extract_dir" "$iconset_dir" "$generated_assets"
}
trap cleanup EXIT

/usr/bin/tar -xzf "$component_archive" -C "$extract_dir"
component_binary="$extract_dir/$component_archive_binary"
if [[ ! -f "$component_binary" ]]; then
  echo "OpenAI App Server 额度组件内容不完整。" >&2
  exit 1
fi
if ! /usr/bin/file "$component_binary" | /usr/bin/grep -q "arm64"; then
  echo "OpenAI App Server 额度组件不是 Apple Silicon 版本。" >&2
  exit 1
fi

/bin/rm -rf "$app_dir" "$iconset_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$iconset_dir"
/bin/cp "$binary_path" "$contents_dir/MacOS/AIQuotaBar"
/bin/cp "$project_root/Info.plist" "$contents_dir/Info.plist"
/bin/cp "$component_binary" "$contents_dir/Resources/$component_resource_name"
/bin/cp "$menu_icon_source" "$contents_dir/Resources/MenuBarHourglassTemplate.png"
/bin/chmod 755 "$contents_dir/MacOS/AIQuotaBar" "$contents_dir/Resources/$component_resource_name"

make_icon() {
  local size="$1"
  local output="$2"
  /usr/bin/sips -z "$size" "$size" "$icon_source" --out "$output" >/dev/null
}

make_icon 16   "$iconset_dir/icon_16x16.png"
make_icon 32   "$iconset_dir/icon_16x16@2x.png"
make_icon 32   "$iconset_dir/icon_32x32.png"
make_icon 64   "$iconset_dir/icon_32x32@2x.png"
make_icon 128  "$iconset_dir/icon_128x128.png"
make_icon 256  "$iconset_dir/icon_128x128@2x.png"
make_icon 256  "$iconset_dir/icon_256x256.png"
make_icon 512  "$iconset_dir/icon_256x256@2x.png"
make_icon 512  "$iconset_dir/icon_512x512.png"
make_icon 1024 "$iconset_dir/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$iconset_dir" -o "$contents_dir/Resources/AppIcon.icns"

/usr/bin/codesign --force --deep --sign - "$app_dir"
/usr/bin/codesign --verify --deep --strict "$app_dir"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$contents_dir/Info.plist")"
if [[ "$bundle_id" != "com.local.aiquotabar" ]]; then
  echo "Bundle ID 校验失败：$bundle_id" >&2
  exit 1
fi

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Info.plist")"
archive_path="$dist_dir/GPT流量监控-$app_version-macOS.zip"
/bin/rm -f "$archive_path"
/usr/bin/ditto -c -k --keepParent "$app_dir" "$archive_path"

echo "已生成：$app_dir"
echo "App 内置组件：Contents/Resources/$component_resource_name"
echo "安装包：$archive_path"
