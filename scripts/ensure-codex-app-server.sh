#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
vendor_dir="$project_root/vendor"
archive="$vendor_dir/codex-app-server-aarch64-apple-darwin-0.151.0.tar.gz"
url="https://github.com/openai/codex/releases/download/rust-v0.151.0/codex-app-server-aarch64-apple-darwin.tar.gz"
expected="09193ef452f35d3558ac5bef21e14d6e3c9763edaa36e6c614126a15fca0ff57"

mkdir -p "$vendor_dir"

verify() {
  [[ -f "$archive" ]] || return 1
  local actual
  actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
  [[ "$actual" == "$expected" ]]
}

if verify; then
  echo "OpenAI Codex App Server 0.151.0 已存在且校验通过。"
  exit 0
fi

/bin/rm -f "$archive"
tmp="$archive.download-$$"
trap '/bin/rm -f "$tmp"' EXIT

echo "正在从 OpenAI 官方 GitHub Release 下载 Codex App Server 0.151.0…"
/usr/bin/curl --fail --location --retry 2 --connect-timeout 15 --output "$tmp" "$url"

actual="$(/usr/bin/shasum -a 256 "$tmp" | /usr/bin/awk '{print $1}')"
if [[ "$actual" != "$expected" ]]; then
  echo "Codex App Server SHA-256 校验失败。" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

/bin/mv "$tmp" "$archive"
trap - EXIT
echo "下载完成并通过 SHA-256 校验。"
