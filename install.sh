#!/usr/bin/env bash
# 安装 tvbox-optimize 到 skills 目录
# 用法: ./install.sh            安装到 ~/.workbuddy/skills/
#       ./install.sh --project  安装到 当前目录/.workbuddy/skills/
set -euo pipefail

NAME="tvbox-optimize"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${1:-}" = "--project" ]; then
  DEST="$(pwd)/.workbuddy/skills"
  SCOPE="项目级"
else
  DEST="${HOME}/.workbuddy/skills"
  SCOPE="用户级"
fi

if [ ! -f "$SRC/SKILL.md" ]; then
  echo "错误: 找不到 $SRC/SKILL.md，请在仓库根目录执行" >&2
  exit 1
fi

mkdir -p "$DEST"

# 已有版本先整体备份，不做删除
if [ -d "$DEST/$NAME" ]; then
  BAK="$DEST/$NAME.bak.$(date +%Y%m%d-%H%M%S)"
  mv "$DEST/$NAME" "$BAK"
  echo "旧版本已备份: $BAK"
fi

mkdir -p "$DEST/$NAME"
cp "$SRC/SKILL.md" "$DEST/$NAME/"
cp -R "$SRC/references" "$DEST/$NAME/"
[ -f "$SRC/README.md" ] && cp "$SRC/README.md" "$DEST/$NAME/"

echo "已安装（${SCOPE}）: $DEST/$NAME"
echo
echo "文件:"
find "$DEST/$NAME" -type f | sed "s|$DEST/$NAME/|  |"
echo
echo "验证: 新开一个对话，说「帮我优化电视盒子」应能触发。"
