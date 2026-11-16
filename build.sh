#!/usr/bin/env bash
# 把 SKILL.md + references 拼成单文件全文，方便不装 skill 的人直接读
# 输出: dist/tvbox-optimize-full.md
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SRC/dist"
OUT="$OUT_DIR/tvbox-optimize-full.md"
mkdir -p "$OUT_DIR"

strip_fm() {
  # 去掉开头 YAML frontmatter（给人读的版本不需要）
  awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$1"
}

{
  echo "# 电视盒子优化手册（完整版）"
  echo
  echo "> 自动生成，请勿手改。源码: SKILL.md + references/"
  echo "> 生成时间: $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "---"
  echo
  echo "## 目录"
  echo
  echo "| 章节 | 内容 |"
  echo "|---|---|"
  echo "| 第一部分 | 主手册：环境确认 → 可行性评估 → 方向选择 → 执行 → 去广告 → 验收 |"
  echo "| 附录 1 | 品牌 / 芯片 / SDK 适配矩阵 |"
  echo "| 附录 2 | 包名清单：必守 / 可停用 / 广告候选 |"
  echo "| 附录 3 | 去广告配置（DNS / 域名层） |"
  echo "| 附录 4 | 低版本 / 低配设备降级路径（API≤19、RAM<1GB） |"
  echo
  echo "---"
  echo
  strip_fm "$SRC/SKILL.md"
  echo
  echo "---"
  echo
  echo "# 附录 1：品牌 / 芯片 / SDK 适配矩阵"
  echo
  tail -n +2 "$SRC/references/device-matrix.md"
  echo
  echo "---"
  echo
  echo "# 附录 2：包名清单"
  echo
  tail -n +2 "$SRC/references/package-lists.md"
  echo
  echo "---"
  echo
  echo "# 附录 3：去广告配置手册"
  echo
  tail -n +2 "$SRC/references/adblock-config.md"
  echo
  echo "---"
  echo
  echo "# 附录 4：低版本 / 低配设备降级路径"
  echo
  tail -n +2 "$SRC/references/lowend-android.md"
} > "$OUT"

echo "已生成: $OUT"
wc -l "$OUT" | awk '{print "行数: "$1}'
