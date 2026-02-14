#!/usr/bin/env bash

set -euo pipefail

BUMP_TYPE="${1:-}"
if [[ -z "$BUMP_TYPE" ]]; then
  echo "缺少参数: major | minor | patch" >&2
  exit 1
fi

case "$BUMP_TYPE" in
  major|minor|patch) ;;
  *)
    echo "无效参数: $BUMP_TYPE（仅支持 major | minor | patch）" >&2
    exit 1
    ;;
esac

BUILD_GRADLE_PATH="app/build.gradle"

if [[ ! -f "$BUILD_GRADLE_PATH" ]]; then
  echo "未找到文件: $BUILD_GRADLE_PATH" >&2
  exit 1
fi

content_version_name_line="$(grep -E '^[[:space:]]*versionName[[:space:]]+"[0-9]+\.[0-9]+\.[0-9]+"[[:space:]]*$' "$BUILD_GRADLE_PATH" | head -n1 || true)"
content_version_code_line="$(grep -E '^[[:space:]]*versionCode[[:space:]]+[0-9]+[[:space:]]*$' "$BUILD_GRADLE_PATH" | head -n1 || true)"

if [[ -z "$content_version_name_line" || -z "$content_version_code_line" ]]; then
  echo "无法从 app/build.gradle 解析 versionName/versionCode" >&2
  exit 1
fi

current_version="$(echo "$content_version_name_line" | sed -E 's/^[[:space:]]*versionName[[:space:]]+"([0-9]+\.[0-9]+\.[0-9]+)"[[:space:]]*$/\1/')"
current_code="$(echo "$content_version_code_line" | sed -E 's/^[[:space:]]*versionCode[[:space:]]+([0-9]+)[[:space:]]*$/\1/')"

IFS='.' read -r major minor patch <<< "$current_version"

case "$BUMP_TYPE" in
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  patch)
    patch=$((patch + 1))
    ;;
esac

new_version="${major}.${minor}.${patch}"
new_code=$((current_code + 1))
new_tag="v${new_version}"

if git rev-parse -q --verify "refs/tags/${new_tag}" >/dev/null 2>&1; then
  echo "Tag 已存在: ${new_tag}" >&2
  exit 1
fi

temp_file="$(mktemp)"
trap 'rm -f "$temp_file"' EXIT

awk -v new_code="$new_code" -v new_version="$new_version" '
BEGIN {
  code_done = 0
  name_done = 0
}
{
  if (!code_done && $0 ~ /^[[:space:]]*versionCode[[:space:]]+[0-9]+[[:space:]]*$/) {
    match($0, /^[[:space:]]*/)
    indent = substr($0, RSTART, RLENGTH)
    print indent "versionCode " new_code
    code_done = 1
    next
  }

  if (!name_done && $0 ~ /^[[:space:]]*versionName[[:space:]]+"[0-9]+\.[0-9]+\.[0-9]+"[[:space:]]*$/) {
    match($0, /^[[:space:]]*/)
    indent = substr($0, RSTART, RLENGTH)
    print indent "versionName \"" new_version "\""
    name_done = 1
    next
  }

  print
}
END {
  if (!code_done || !name_done) {
    exit 2
  }
}
' "$BUILD_GRADLE_PATH" > "$temp_file"

mv "$temp_file" "$BUILD_GRADLE_PATH"
trap - EXIT

git add app/build.gradle

if git diff --cached --quiet; then
  echo "没有检测到版本变更，提交已取消" >&2
  exit 1
fi

git commit -m "chore: bump version to ${new_version}"
git push
git tag "$new_tag"
git push origin "$new_tag"

echo "已完成: versionName=${new_version}, versionCode=${new_code}, tag=${new_tag}"
