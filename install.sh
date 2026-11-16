#!/usr/bin/env bash
# skillbox 安装器
#
#   ./install.sh                  全部 skill → ~/.workbuddy/skills/
#   ./install.sh <name>...        指定 skill
#   ./install.sh --project        改装到 当前目录/.workbuddy/skills/
#   ./install.sh --list           列出可安装的 skill
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="$ROOT/skills"

if [ ! -d "$SRC_ROOT" ]; then
  echo "错误: 找不到 $SRC_ROOT，请在仓库根目录执行" >&2
  exit 1
fi

DEST="${HOME}/.workbuddy/skills"
SCOPE="用户级"
TARGETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --project) DEST="$(pwd)/.workbuddy/skills"; SCOPE="项目级" ;;
    --list)
      echo "可安装的 skill:"
      for d in "$SRC_ROOT"/*/; do
        n=$(basename "$d")
        [ "${n#_}" != "$n" ] && continue
        printf "  %-24s %s\n" "$n" "$(sed -n 's/^description: //p' "$d/SKILL.md" 2>/dev/null | head -1 | cut -c1-70)"
      done
      exit 0 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "未知参数: $1" >&2; exit 1 ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

# 未指定则装全部（跳过 _ 开头的模板目录）
if [ ${#TARGETS[@]} -eq 0 ]; then
  for d in "$SRC_ROOT"/*/; do
    n=$(basename "$d")
    [ "${n#_}" != "$n" ] && continue
    TARGETS+=("$n")
  done
fi

mkdir -p "$DEST"

for name in "${TARGETS[@]}"; do
  src="$SRC_ROOT/$name"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "跳过 $name: 没有 SKILL.md" >&2
    continue
  fi

  # 已有版本整体备份，不做删除
  if [ -d "$DEST/$name" ]; then
    BAK="$DEST/$name.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$DEST/$name" "$BAK"
    echo "  $name: 旧版本备份 → $BAK"
  fi

  mkdir -p "$DEST/$name"
  cp "$src/SKILL.md" "$DEST/$name/"
  [ -d "$src/references" ] && cp -R "$src/references" "$DEST/$name/"
  [ -f "$src/README.md" ] && cp "$src/README.md" "$DEST/$name/"
  echo "  $name: 已安装"
done

echo
echo "目标目录（${SCOPE}）: $DEST"
echo "验证: 新开对话，说一句自然语言（如「帮我优化电视盒子」）应能触发。"
