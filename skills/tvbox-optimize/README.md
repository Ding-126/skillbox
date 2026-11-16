# tvbox-optimize

一个给 AI Agent 用的、也给人读的**安卓电视盒子 / 智能电视优化执行手册**。

不是教程合集，是操作规程：从"不知道电视是什么型号"走到"去广告落地并验证通过"，每一步都有判定依据和回滚命令。

---

## 它解决的问题

网上关于电视盒子优化的内容有三个通病：

1. **只给结论不给依据**。"禁用这三个包"——你的固件里可能根本没有这三个包，或者它叫别的名字。
2. **假设 API 存在**。大量教程默认 `pm disable` 可用。定制固件里厂商会从 `platform.xml` 删掉 shell 的权限，命令直接报 SecurityException。
3. **没有回滚**。改完黑屏，遥控器救不回来，教程作者不负责。

这份文档的写法是反过来的：**先探测设备能力，再决定走哪条路；每条破坏性命令配回滚；验证不过不许进下一步。**

---

## 核心设计

| 原则 | 说明 |
|---|---|
| **先探测，后动手** | §1.5 四组命令摸清固件裁了什么，再选方案 |
| **五道门禁** | 可达 → ADB 可控 → 权限深度 → 系统锁定 → 硬件余量，任一失败就降级，不硬上 |
| **冻结优于删除** | `disable` / `block` 优先，`uninstall` 最后；能 `unblock` 的才是好方案 |
| **一次一个变量** | 批量改完出问题无法定位；每批 ≤10 个包，改完重启验证 |
| **广告从最便宜的开始** | 先按 OK 键跳过 → 再 DNS → 再停服务 → 最后才动系统 |

---

## 快速开始

### 方式一：装成 skill（给 WorkBuddy / Claude Code 类工具用）

在 skillbox 仓库根目录执行：

```bash
git clone https://github.com/<your-name>/skillbox.git && cd skillbox

./install.sh tvbox-optimize    # 装到 ~/.workbuddy/skills/tvbox-optimize
./install.sh --project         # 或装到当前项目 .workbuddy/skills/
```

装完后在对话里说"帮我优化电视盒子"即可触发。

### 方式二：当文档读（不装任何东西）

```bash
./build.sh tvbox-optimize      # 生成 dist/tvbox-optimize-full.md（单文件全文）
```

单文件版可直接发微信 / 贴博客 / 丢给任何 AI 当上下文。

### 方式三：手动指定

把本目录（`SKILL.md` + `references/`）整个复制到你的 skills 目录，改名为 `tvbox-optimize`。`SKILL.md` 的 frontmatter 已符合规范。

---

## 内容结构

| 文件 | 回答什么 |
|---|---|
| `SKILL.md` | 主流程：环境确认 → 可行性评估 → 方向选择 → 执行 → 去广告 → 验收 |
| `references/device-matrix.md` | 品牌 ADB 开启路径、芯片可刷性、SDK 能力边界、自动判级脚本 |
| `references/package-lists.md` | 必守包清单、可停用类型、运营商包判据、批次模板、实测清单 |
| `references/adblock-config.md` | DNS 三方案（AdGuard Home / Private DNS / hosts）、域名分类、抓包方法论 |
| `references/lowend-android.md` | **API≤19 / RAM<1GB 降级路径**：`pm block`、权限被剥、厂商白名单、桌面接管三路径 |

---

## 实测案例

文档里的数据不是编的。主案例是一台 **创维 Q0101（自报 Q0108，企鹅极光 T1 青春版）**：

| | |
|---|---|
| 硬件 | 全志 H2 双核 A7 1.0GHz / **507MB RAM** / 4G 存储 |
| 系统 | Android **4.4.2 / API19** / 1280×720@160dpi |
| root | 无（`dev-keys` 但 platform key 厂商自签） |

优化结果：

| 指标 | 前 | 后 |
|---|---|---|
| 空闲内存 | 55 MB | 226 MB |
| 桌面占用 | 82 MB | 26 MB |
| 开机落点 | 原桌面（带广告位） | 极简桌面 |
| 崩溃 | 桌面选择器必崩 | 0 |

过程中踩到并写进文档的坑：`pm disable` 权限被剥 → 走 `pm block`；API19 没有 `cmd package`；厂商白名单服务器下发每 2 小时覆盖；包名前缀可绕过白名单；`system uid` 路线证伪；杀后台导致冷启动慢 3.4 秒。

---

## 适用 / 不适用

**适用**：Android TV、AOSP TV、运营商 IPTV 盒子、外贸 Amlogic / Rockchip 盒子、智能电视、投影。

**不适用**：非 Android 的封闭自研系统；以及任何**你不拥有**的设备。

---

## 边界

- 只操作自有设备。扫描、接管他人网络内的设备是违法的。
- 不提供付费内容破解、不提供盗版源、不提供会员墙绕过方案。
- 所有涉及刷机的步骤都要求"手上有官方固件包"，没有就禁止动手——这条在文档里是硬红线。

---

## 许可

MIT。拿去用、改、再发布都行。

如果这份文档帮你救回一台本该吃灰的盒子，那它的目的就达到了。
