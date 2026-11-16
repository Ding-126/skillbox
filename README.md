# skillbox

个人 Agent 技能合集。每个 skill 是一份**可执行的操作规程**，不是教程文章。

装进 agent 就能用，不装也能当手册读。

---

## 收录

| Skill | 一句话 | 适用 |
|---|---|---|
| [`tvbox-optimize`](skills/tvbox-optimize/) | 安卓电视盒子 / 智能电视优化：设备发现、可行性评估、去广告、系统瘦身 | Android TV、AOSP TV、IPTV 盒子、智能电视、投影 |

---

## 安装

```bash
git clone https://github.com/Ding-126/skillbox.git
cd skillbox

./install.sh                    # 全部装到 ~/.workbuddy/skills/
./install.sh tvbox-optimize     # 只装一个
./install.sh --project          # 装到当前项目 .workbuddy/skills/
./install.sh --list             # 看有哪些可装
```

装完新开对话，说一句自然语言（如"帮我优化电视盒子"）即可触发。

## 只想要文档

```bash
./build.sh tvbox-optimize       # 生成 dist/tvbox-optimize-full.md（单文件全文）
./build.sh                      # 全部生成
```

单文件版可直接发人、贴博客、或作为上下文丢给任何模型。

---

## 目录结构

```
skillbox/
├── README.md                     ← 你在这里（合集索引）
├── install.sh                    ← 安装器，支持单装/全装
├── build.sh                      ← 打包器，把 skill 拼成单文件
├── _template/                    ← 新增 skill 的起点
│   └── SKILL.md
└── skills/
    └── <skill-name>/
        ├── SKILL.md              ← 唯一入口，agent 读这个
        ├── README.md             ← 人看的说明（可选但推荐）
        └── references/           ← 按需加载的细节（可选）
```

---

## 新增一个 skill 的规范

这个仓库要能长期加东西，所以约定死几条，别每次重新想。

**1. 目录**

```
skills/<kebab-case-name>/SKILL.md
```

名字用英文字母、数字、连字符，不用空格和中文（路径会被引用）。

**2. `SKILL.md` 必须有 frontmatter**

```yaml
---
name: <与目录名完全一致>
description: <一句话能力 + 触发词。写清"什么时候该用它"，这是 agent 决定是否加载的唯一依据>
---
```

`description` 决定命中率。**把用户会说的原话写进去**（"去广告"、"卡顿"、"卸载预装"），不要只写抽象能力。

**3. 正文写规程，不写科普**

- 先给判定条件，再给动作。
- 每条破坏性操作必须配回滚命令。
- 大表格、清单、命令速查放 `references/`，`SKILL.md` 只留主干和指针。

**4. 收尾三件套**

- 开头有"文档结构 / 使用顺序"表。
- 中间有"验证方式"（怎么算做完了）。
- 结尾有"不适用 / 红线"（什么情况别用）。

**5. 自测**

```bash
./build.sh <name>        # 能拼成单文件，说明文件引用没断
./install.sh <name>      # 能装上，说明结构合规
```

---

## 边界

这里的 skill 只处理**你有权操作的东西**。涉及他人设备、绕过付费、破解版权内容的，一律不收录。

---

## 许可

MIT。拿去用、改、再发布都行。
