#!/usr/bin/env bash
# 把 skill 的 SKILL.md + references 拼成单文件全文，方便不装 skill 的人直接读
#
#   ./build.sh                生成全部
#   ./build.sh <name> ...     生成指定 skill
# 输出: dist/<name>-full.md
#
# references 拼接顺序：优先读 references/_order.txt（每行一个文件名），
# 未列出的按文件名排序排在后面。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$ROOT/skills"
OUT_DIR="$ROOT/dist"
mkdir -p "$OUT_DIR"

[ -d "$SRC_ROOT" ] || { echo "错误: 找不到 $SRC_ROOT" >&2; exit 1; }

TARGETS=()
if [ $# -eq 0 ]; then
  for d in "$SRC_ROOT"/*/; do
    n=$(basename "$d")
    [ "${n#_}" != "$n" ] && continue
    TARGETS+=("$n")
  done
else
  TARGETS=("$@")
fi

# 去掉开头 YAML frontmatter
strip_fm() { awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$1"; }

# 取 md 文件的一级标题，没有则退回文件名
title_of() {
  local t
  t=$(sed -n 's/^# //p' "$1" | head -1)
  [ -n "$t" ] && echo "$t" || basename "$1" .md
}

# 输出有序的 reference 列表
order_refs() {
  local dir="$1" f n
  if [ -f "$dir/references/_order.txt" ]; then
    while IFS= read -r n <&3; do
      [ -z "$n" ] && continue
      case "$n" in \#*) continue ;; esac
      [ -f "$dir/references/$n" ] && echo "$dir/references/$n"
    done 3< "$dir/references/_order.txt"
  fi
  for f in "$dir"/references/*.md; do
    [ -f "$f" ] || continue
    if [ -f "$dir/references/_order.txt" ] && grep -qxF "$(basename "$f")" "$dir/references/_order.txt"; then
      continue
    fi
    echo "$f"
  done
}

for name in "${TARGETS[@]}"; do
  src="$SRC_ROOT/$name"
  [ -f "$src/SKILL.md" ] || { echo "跳过 $name: 没有 SKILL.md" >&2; continue; }
  out="$OUT_DIR/$name-full.md"

  main_title=$(sed -n 's/^# //p' "$src/SKILL.md" | head -1)
  [ -n "$main_title" ] || main_title="$name"

  {
    echo "# ${main_title}（完整版）"
    echo
    echo "> 由 build.sh 自动生成，请勿手改。源码: skills/$name/"
    echo "> 生成时间: $(date '+%Y-%m-%d %H:%M')"
    echo
    echo "---"
    echo

    # 正文，去掉与上方大标题重复的那行 H1
    strip_fm "$src/SKILL.md" | awk -v t="# $main_title" 'BEGIN{d=0} {if(!d && $0==t){d=1; next} print}'

    order_refs "$src" | while IFS= read -r ref; do
      echo
      echo "---"
      echo
      echo "# $(title_of "$ref")"
      echo
      tail -n +2 "$ref"
    done
  } > "$out"

  printf "  已生成: %s (%s 行)\n" "$out" "$(wc -l < "$out" | tr -d ' ')"
done
