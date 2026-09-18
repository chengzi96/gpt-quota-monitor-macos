#!/bin/bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")" && pwd)"

product_name="GPT流量监控"
app_name="$product_name.app"
legacy_app_name="额度栏.app"
bundle_id="com.local.aiquotabar"
install_target="/Applications/$app_name"
legacy_target="/Applications/$legacy_app_name"
user_duplicate="$HOME/Applications/$app_name"
user_legacy_duplicate="$HOME/Applications/$legacy_app_name"
log_path="$HOME/Desktop/GPT流量监控-安装日志.txt"
staged_target="/Applications/.gpt-flow-monitor-install-$$.app"
backup_target="/Applications/.gpt-flow-monitor-backup-$$.app"
backup_original=""
needs_sudo=0
install_committed=0
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

register_app() {
  local app_path="$1"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -u "$app_path" >/dev/null 2>&1 || true
    "$lsregister" -f "$app_path" >/dev/null 2>&1 || true
  fi
  /usr/bin/touch "$app_path" >/dev/null 2>&1 || true
  /usr/bin/mdimport "$app_path" >/dev/null 2>&1 || true
}

unregister_app() {
  local app_path="$1"
  if [[ -x "$lsregister" && -e "$app_path" ]]; then
    "$lsregister" -u "$app_path" >/dev/null 2>&1 || true
  fi
}

exec > >(tee "$log_path") 2>&1

show_dialog() {
  /usr/bin/osascript -e "display dialog \"$1\" with title \"GPT流量监控安装器\" buttons {\"好\"} default button \"好\"" >/dev/null 2>&1 || true
}

on_error() {
  show_dialog "安装没有完成。详细信息已保存到桌面的《GPT流量监控-安装日志.txt》。"
}
trap on_error ERR

existing_bundle_id() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist" 2>/dev/null || true
}

rm_path() {
  if [[ "$needs_sudo" -eq 1 ]]; then sudo /bin/rm -rf "$1"; else /bin/rm -rf "$1"; fi
}

mv_path() {
  if [[ "$needs_sudo" -eq 1 ]]; then sudo /bin/mv "$1" "$2"; else /bin/mv "$1" "$2"; fi
}

cleanup_stage() {
  if [[ -e "$staged_target" ]]; then
    rm_path "$staged_target" >/dev/null 2>&1 || true
  fi
  if [[ "$install_committed" -eq 0 && -n "$backup_original" && -e "$backup_target" ]]; then
    if [[ -e "$install_target" ]]; then rm_path "$install_target" >/dev/null 2>&1 || true; fi
    mv_path "$backup_target" "$backup_original" >/dev/null 2>&1 || true
  elif [[ -e "$backup_target" ]]; then
    rm_path "$backup_target" >/dev/null 2>&1 || true
  fi
}
trap cleanup_stage EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  show_dialog "这个安装包只能在 Mac 上使用。"
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  show_dialog "当前版本仅支持 Apple Silicon Mac。"
  exit 1
fi

product_version="$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)"
product_major="${product_version%%.*}"
if [[ -z "$product_major" || "$product_major" -lt 26 ]]; then
  show_dialog "GPT流量监控 v0.3.27 使用 macOS 26 原生 Liquid Glass，仅支持 macOS 26 或更高版本。"
  exit 1
fi

if ! command -v swift >/dev/null 2>&1 || ! command -v codesign >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
  show_dialog "首次安装需要 Xcode / Apple Command Line Tools 26。接下来会打开 Apple 官方安装窗口，完成后请再次双击本安装器。"
  xcode-select --install >/dev/null 2>&1 || true
  trap - ERR
  exit 0
fi

sdk_version="$(/usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
sdk_major="${sdk_version%%.*}"
if [[ -z "$sdk_major" || "$sdk_major" -lt 26 ]]; then
  show_dialog "当前开发工具不包含 macOS 26 SDK。请先更新到 Xcode / Apple Command Line Tools 26 后再安装。"
  trap - ERR
  exit 1
fi

for candidate in "$install_target" "$legacy_target"; do
  if [[ -e "$candidate" ]]; then
    installed_id="$(existing_bundle_id "$candidate")"
    if [[ "$installed_id" != "$bundle_id" ]]; then
      show_dialog "“应用程序”中已有同名但来源不同的 App。为避免误删，安装已停止。"
      trap - ERR
      exit 1
    fi
  fi
done

if [[ ! -w "/Applications" ]]; then needs_sudo=1; fi
for candidate in "$install_target" "$legacy_target"; do
  if [[ -e "$candidate" && ! -w "$candidate" ]]; then needs_sudo=1; fi
done

echo "正在准备并构建 GPT流量监控 v0.3.27…"
cd "$source_dir"
/bin/chmod +x scripts/build-app.sh
./scripts/build-app.sh

built_app="$source_dir/dist/$app_name"
if [[ ! -d "$built_app" ]]; then
  echo "没有找到构建完成的 App：$built_app" >&2
  exit 1
fi
if [[ "$(existing_bundle_id "$built_app")" != "$bundle_id" ]]; then
  echo "构建产物 Bundle ID 不正确，停止安装。" >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$built_app"

echo "正在准备安全替换…"
rm_path "$staged_target" >/dev/null 2>&1 || true
rm_path "$backup_target" >/dev/null 2>&1 || true
if [[ "$needs_sudo" -eq 0 ]]; then
  /usr/bin/ditto "$built_app" "$staged_target"
else
  sudo /usr/bin/ditto "$built_app" "$staged_target"
  sudo /usr/sbin/chown -R "$(id -u):$(id -g)" "$staged_target"
fi

if [[ "$(existing_bundle_id "$staged_target")" != "$bundle_id" ]]; then
  echo "待安装 App Bundle ID 校验失败。" >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$staged_target"

echo "正在退出旧版本…"
unregister_app "$install_target"
unregister_app "$legacy_target"
/usr/bin/osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
/bin/sleep 1
/usr/bin/pkill -x AIQuotaBar >/dev/null 2>&1 || true

if [[ -e "$install_target" ]]; then
  backup_original="$install_target"
elif [[ -e "$legacy_target" ]]; then
  backup_original="$legacy_target"
fi

if [[ -n "$backup_original" ]]; then
  mv_path "$backup_original" "$backup_target"
fi

if ! mv_path "$staged_target" "$install_target"; then
  exit 1
fi

if [[ "$needs_sudo" -eq 1 ]]; then
  sudo /usr/sbin/chown -R "$(id -u):$(id -g)" "$install_target"
fi

if ! /usr/bin/codesign --verify --deep --strict "$install_target"; then
  exit 1
fi

install_committed=1
if [[ -e "$backup_target" ]]; then rm_path "$backup_target"; fi

if [[ -e "$legacy_target" && "$legacy_target" != "$install_target" && "$(existing_bundle_id "$legacy_target")" == "$bundle_id" ]]; then
  trash_name="$HOME/.Trash/额度栏-旧副本-$(date +%Y%m%d-%H%M%S).app"
  if [[ "$needs_sudo" -eq 1 ]]; then
    sudo /bin/mv "$legacy_target" "$trash_name" || sudo /bin/rm -rf "$legacy_target"
  else
    /bin/mv "$legacy_target" "$trash_name" || /bin/rm -rf "$legacy_target"
  fi
fi

for duplicate in "$user_duplicate" "$user_legacy_duplicate"; do
  if [[ -d "$duplicate" && "$(existing_bundle_id "$duplicate")" == "$bundle_id" ]]; then
    trash_name="$HOME/.Trash/$(basename "$duplicate" .app)-旧副本-$(date +%Y%m%d-%H%M%S).app"
    /bin/mv "$duplicate" "$trash_name"
  fi
done

/usr/bin/xattr -dr com.apple.quarantine "$install_target" >/dev/null 2>&1 || true
register_app "$install_target"

installed_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$install_target/Contents/Info.plist")"
installed_build="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$install_target/Contents/Info.plist")"
/usr/bin/open -R "$install_target" >/dev/null 2>&1 || true
/bin/sleep 0.3
/usr/bin/open "$install_target"

/bin/sleep 1
if ! /usr/bin/pgrep -x AIQuotaBar >/dev/null 2>&1; then
  echo "App 启动失败：AIQuotaBar 进程没有保持运行。" >&2
  exit 1
fi

trap - ERR
show_dialog "GPT流量监控 $installed_version（Build $installed_build）已安装并启动。"
echo "安装完成：$install_target"
