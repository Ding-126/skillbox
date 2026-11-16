---
name: tvbox-optimize
description: 安卓电视盒子 / 智能电视（Android TV、AOSP TV、运营商 IPTV 盒子、外贸 Amlogic 盒子）的局域网发现、可优化性评估、去广告、系统瘦身与配置调优的执行手册。当用户提到电视盒子、机顶盒、智能电视卡顿/开机广告/自动更新、ADB 调试、卸载预装应用、换桌面、刷机、DNS 去广告时使用。
---

# 电视盒子优化 Skill

一套从"不知道电视是什么型号"走到"去广告落地并验收"的完整操作规程。所有结论必须由设备实测数据支撑，禁止凭品牌印象下判断。

## 0. 文档结构与使用方式

| 章节 | 回答的问题 | 产出物 | 是否必做 |
|---|---|---|---|
| 1 基础依赖与环境确认 | 设备在哪、是什么、什么系统 | 设备档案表（§1.4） | 必做，缺一项不得进入下一步 |
| 2 可优化性评估 | 这台设备能不能优化、能到什么程度 | 评级 A/B/C/D + 可优化项清单 | 必做 |
| 3 优化方向分类 | 具体可以动哪些地方 | 选定方向（可多选） | 必做 |
| 4 处理方案与操作步骤 | 每一步怎么执行、怎么验证、怎么回滚 | 执行记录 | 仅对已选方向 |
| 5 去广告与配置 | 广告从哪来、怎么定向掐掉 | 拦截层级 + 生效验证 | 仅对已选方向 |
| 6 验收与回滚 | 怎么证明有效、坏了怎么退 | 观察期结论 | 必做 |
| 附录 A/B/C | 命令、红线、故障对照 | — | 查阅 |

配套参考表（按症状查，不按顺序读）：

| 文件 | 用途 |
|---|---|
| `references/device-matrix.md` | 品牌 ADB 开启路径、芯片可刷性、SDK 能力边界 |
| `references/package-lists.md` | 必守包清单、可停用类型、批次模板 |
| `references/adblock-config.md` | DNS 三方案、域名分类策略、抓包方法论 |
| `references/lowend-android.md` | **API≤19 / RAM<1GB 的降级路径**：`pm block`、权限被剥、厂商白名单、桌面接管三路径 |

**使用顺序不可跳**：跳过 §1 直接执行 §4 的命令，是变砖和遥控失灵的唯一起因。

**三个全局红线**（任何阶段违反即中止）：

1. 只操作自有设备。不碰他人网络内的设备，不做付费内容破解、不接入盗版源。
2. 每条破坏性命令必须提前记录回滚命令，并确认 `pm` 类操作可通过 `cmd package install-existing` 恢复。
3. 同一时间只改一个变量。改完观察，再改下一个。批量执行后出问题无法定位。

---

## 1. 基础依赖与环境确认

### 1.1 工具清单（按必需度排序）

| 工具 | 用途 | 必需 | 获取 |
|---|---|---|---|
| `adb`（platform-tools） | 90% 操作的总入口 | 必需 | Android SDK Platform-Tools 官方包 |
| `nmap` | 网段存活 + 端口扫描 | 必需 | `brew install nmap` / `apt install nmap` |
| `arp` / `ip neigh` | 读本机 ARP 表找设备 | 必需 | 系统自带 |
| `curl` | 探测 HTTP 管理页 | 必需 | 系统自带 |
| `dns-sd`(macOS) / `avahi-browse`(Linux) | mDNS 发现 TV/投屏服务 | 推荐 | 系统自带 / `apt install avahi-utils` |
| `scrcpy` | 免遥控器远程操作画面 | 推荐 | 开源，见 §7 |
| `universal-android-debloater`（UAD） | 图形化批量停用预装包 | 推荐 | 开源，见 §7 |
| 路由器管理权限 | 层三拦截、静态 IP、看在线设备表 | 推荐 | — |
| `python3` | 批量采集/生成报告 | 可选 | — |

前置条件：操作机与盒子必须在**同一子网**（同一路由器下的 LAN 或同一 Wi-Fi SSID，且未开 AP 隔离）。跨网段、访客网络、Mesh 的子节点隔离都会导致 `adb connect` 超时。

### 1.2 局域网设备发现与识别

四步收敛，从粗到细：

**Step 1 网段存活扫描**

```bash
# macOS/Linux，先确认本机网段
ipconfig getifaddr en0            # macOS Wi-Fi
ip -4 addr show | grep inet       # Linux

nmap -sn 192.168.1.0/24 -oG - | grep Up
```

**Step 2 ARP 表交叉验证**（nmap 可能被 ICMP 屏蔽，ARP 不会）

```bash
arp -an | grep -v incomplete      # macOS
ip neigh show                     # Linux
```

**Step 3 端口指纹识别**（决定后续所有可行性）

```bash
nmap -p 5555,5037,6466,6467,8008,8009,8080,9080,80,443,1900 --open 192.168.1.0/24
```

| 端口 | 协议/服务 | 判定意义 |
|---|---|---|
| 5555 | ADB over TCP | **最关键**。开放 = 大概率可直接接管 |
| 6466/6467 | Android TV Remote Service v2 | 安卓 TV 设备；配对后可当遥控器 |
| 8008/8009 | Google Cast | 带 Chromecast 的 TV / 盒子 |
| 9080 | 部分国产盒子 Web 管理 | 厂商定制系统特征 |
| 1900 | SSDP/UPnP | 设备会自报 `friendlyName` 与型号 |
| 80/8080 | Web 管理页 | 外贸盒子、部分 IPTV 网关 |

**Step 4 服务名与厂商信息**

```bash
# mDNS 抓 TV 遥控/投屏服务，能直接拿到设备名
dns-sd -B _androidtvremote2._tcp local.     # macOS，Ctrl-C 停止
avahi-browse -r _androidtvremote2._tcp      # Linux

# SSDP 抓 UPnP 描述（含 modelName / friendlyName）
curl -s -H 'Content-Type: text/xml; charset="utf-8"' \
  -H 'SOAPACTION: "urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo"' \
  http://192.168.1.x:1900/ 2>/dev/null
```

**Step 5 厂商归属判定**（MAC OUI）

```bash
# 取 MAC 前 3 段查厂商
arp -an | grep 192.168.1.x
grep -i "A4:DA:22" /usr/share/nmap/nmap-mac-prefixes   # 需装了 nmap
```

OUI 只用于**缩小范围**，不用于下结论——大量盒子用方案商公版主板，OUI 可能指向 Amlogic/Realtek 而非品牌。最终型号一律以 §1.3 的 `getprop` 为准。

**DHCP 主机名是最高性价比线索**：路由器后台的客户端名称常见 `MiBox4`, `MiTV-MSSP2`, `SkyworthBox`, `Hisense-TV`, `MAGICBOX`, `S905X3` 等，直接给出品牌或芯片平台。

### 1.3 型号 / 固件 / 系统版本判定

**优先路径：ADB（最准确）**

```bash
adb connect 192.168.1.x:5555
adb devices -l          # 显示 unauthorized 时：回电视上点"允许调试"
```

```bash
adb shell getprop | grep -E 'ro\.product|ro\.build|ro\.debuggable|ro\.secure' 
```

逐项取值（这些是后续所有判断的输入）：

```bash
adb shell getprop ro.product.brand            # 品牌
adb shell getprop ro.product.model            # 型号
adb shell getprop ro.product.device           # 设备代号（刷机包匹配关键）
adb shell getprop ro.product.manufacturer     # 代工厂
adb shell getprop ro.build.version.release    # Android 版本
adb shell getprop ro.build.version.sdk        # API level
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.build.display.id         # 固件版本号（OTA 比对用）
adb shell getprop ro.build.fingerprint        # 完整指纹（唯一标识固件）
adb shell getprop ro.build.type               # user / userdebug / eng
adb shell getprop ro.debuggable               # 1 = 可直接 root
adb shell getprop ro.secure                   # 0 = adbd 以 root 运行
adb shell getprop ro.product.cpu.abi          # 架构，决定刷机包
adb shell getprop ro.config.low_ram           # true = 低内存机型，性能项要更激进
```

**关键判断依据**：

- `ro.build.type = userdebug` 或 `ro.debuggable = 1` → 具备 root 条件，可进入系统层优化（§3-1/§3-4）。
- `ro.secure = 1` 且无 `su` → 只能做应用层优化，不要尝试提权。
- `ro.build.version.sdk < 26`（Android 8 以下）→ 现代流媒体客户端装不上，优化收益低于换盒子。
- `security_patch` 落后当前时间 3 年以上 → 有安全风险，但**不代表必须升级**（升级常带回广告）。

**root / 提权状态复核**：

```bash
adb shell id                                  # uid=0 直接是 root
adb shell which su; adb shell su -c id        # 有 su 且能执行
adb shell magisk -v                           # Magisk 版本
adb shell getprop ro.boot.verifiedbootstate   # green = 未解锁 BL
```

**降级路径：ADB 不可用时的识别手段**

1. 设置 → 关于 / 系统信息，抄下型号与版本号（厂商 UI 常改名：`设备信息`/`系统升级`/`关于本机`）。
2. 机身背面/底部铭牌：型号、输入电压、认证号。
3. 包装盒条形码与 SN（SN 前几位常含代工厂与批次）。
4. HDMI 源信息：电视端显示的分辨率/刷新率/HDR 能力，侧证芯片等级。
5. 系统升级页的"当前版本"，与厂商官网/论坛固件列表比对，反推硬件代际。

没有任何一项能拿到型号时，评级直接落入 **C 或 D**（见 §2），不做系统层操作。

### 1.4 设备档案表（必填，缺失即阻断）

把这 14 项填完再往下走。获取方式与判断用途一一对应：

| # | 字段 | 获取方式 | 为什么必填 | 判断依据 |
|---|---|---|---|---|
| 1 | 局域网 IP | nmap / 路由器 DHCP 表 | 所有连接的目标 | 必须与操作机同子网 |
| 2 | MAC + OUI 厂商 | `arp -an` | 区分公版主板 vs 品牌定制 | OUI 只作线索 |
| 3 | 品牌 | `ro.product.brand` | 决定 ADB 开启路径与包名体系 | 见 `references/device-matrix.md` |
| 4 | 型号 | `ro.product.model` | 定位固件与已知坑 | 精确到后缀（如 `MSSP2`） |
| 5 | 设备代号 | `ro.product.device` | 刷机包唯一匹配键 | 不符**绝对不刷** |
| 6 | Android 版本 / SDK | `ro.build.version.*` | 决定可用 API 与 DNS 能力 | SDK≥28 才有 Private DNS |
| 7 | 固件版本 | `ro.build.display.id` | OTA 比对、防回滚 | 记录原始值以便还原 |
| 8 | build 指纹 | `ro.build.fingerprint` | 同型号多固件分支的区分 | 刷机前必须先备份 |
| 9 | build 类型 | `ro.build.type` / `ro.debuggable` | 判断能否 root | userdebug → 可 root |
| 10 | root 状态 | `adb shell id` / `which su` | 决定可用方案池 | 无 root → 仅应用层 |
| 11 | 5555 是否开放 | nmap | 决定是否需先开 ADB | 关闭则走 UI 开启流程 |
| 12 | RAM / 可用存储 | `/proc/meminfo`、`df -h /data` | 决定性能优化力度 | 见 §2 阈值 |
| 13 | 是否运营商定制 | 包名含 `iptv`/`auth`、UI 有运营商 LOGO | 决定能否动系统与网络 | 定制机风险显著更高 |
| 14 | 遥控器类型 | 红外 / 蓝牙 / 语音 | 决定改桌面后键位是否要重映射 | 蓝牙遥控易失配 |
| 15 | **ADB 是否持久** | 重启一次后 `adb connect` 是否自动可用 | 决定失败后能否远程救回 | 不持久 → 只做"无 ADB 也能自愈"的改动 |

资源采集命令：

```bash
adb shell cat /proc/meminfo | head -3          # MemTotal 换算 MB
adb shell df -h /data                          # 可用存储
adb shell dumpsys meminfo | head -20           # 实际占用
adb shell top -n 1 -m 10 -o %CPU,RES,CMDLINE   # 占 CPU 的进程
adb shell pm list packages | wc -l             # 装机数量，>250 通常臃肿
```

### 1.5 能力探测（定制固件的必做项）

**不要假设文档里的命令在你的设备上存在。** 厂商定制固件会删命令、删权限、加白名单。四组探测，5 分钟：

```bash
adb shell pm 2>&1 | head -40                                    # pm 有哪些子命令
adb shell which cmd; adb shell which su                         # cmd/su 是否存在
adb shell cat /system/etc/permissions/platform.xml | grep -c 'uid="shell"'   # 0 = shell 权限被整块剥离
adb shell settings list system | head -5                        # settings 命名空间可读性
```

| 探测结果 | 影响 |
|---|---|
| `cmd` 不存在（API<21 常态） | 无 `set-home-activity`、无 `install-existing`，恢复只能靠 `unblock` 或重装 APK |
| `platform.xml` 无 `uid="shell"` | `pm disable` 报 SecurityException，改走 `pm block` |
| `adb root` 提示成功但 `id` 仍是 2000 | adbd 被裁，不要继续尝试提权 |
| `persist.adb.tcp.port` 写入被拒 | ADB 重启即失联，所有改动必须能无 ADB 自愈 |

细节与备选路径见 `references/lowend-android.md` §1、§5。

---

## 2. 优化前的可优化性评估标准

### 2.1 五道门禁（逐门通过，任一失败即降级）

| 门 | 检查项 | 通过标准 | 失败含义 |
|---|---|---|---|
| **G0 可达性** | ping / 端口扫描 | 同子网可达，至少 1 个管理端口开放 | 网络隔离或设备离线，无法远程操作 |
| **G1 可控性** | ADB 可开启并连接成功 | `adb devices` 显示 `device`（非 `unauthorized`/`offline`） | 只能做遥控器可见范围内的设置项 |
| **G2 权限深度** | `ro.build.type` / `su` / `pm disable` 实测 RC | 至少满足其一：userdebug、有 su、**`pm disable` 或 `pm block` 可用** | 无法改 hosts、无法冻结系统服务 |
| **G3 系统锁定** | BL 状态、OTA 强制、运营商签名校验 | BL 未锁 或 无需刷机即可达成目标 | 刷机路线关闭；仅剩应用层 |
| **G4 硬件余量** | RAM、存储、SDK 版本 | RAM≥2GB 且可用存储≥1.5GB 且 SDK≥26 | **不等于不可优化**：只能做极限瘦身 + 换桌面，别指望跑新应用（见 §2.4） |
| **G5 风险比** | 保修、鉴权依赖、能否接受变砖 | 有明确回滚路径 或 设备可弃 | 不建议动手 |

### 2.2 分级结论（A/B/C/D）

| 等级 | 定义 | 判定条件 | 可执行范围 |
|---|---|---|---|
| **A 全量可优化** | 系统层与应用层都能动 | G0~G3 全过 且 G4 达标 | §3 全部方向，含 root 级 tweak |
| **B 应用层可优化** | 不能改系统分区但能装/停应用 | G0/G1 过，G2/G3 失败，G4 达标 | 目录 1、3、5、6、8（部分） |
| **C 仅外围拦截** | 盒子本身动不了 | G1 失败或 G5 风险过高 | 目录 5（路由器侧 DNS）、8 外围 |
| **D 不建议优化** | 收益为零或风险不可控 | G1 失败且无外围替代，或过保且为唯一收视设备 | 建议换设备 / 只走 L0 手动跳过 |

### 2.3 评分卡（用于同类设备横向比较 / 汇报）

每项 0–2 分，总分 12：

| 维度 | 0 分 | 1 分 | 2 分 |
|---|---|---|---|
| 系统开放度 | 无 ADB | 有 ADB 无 root | userdebug/有 root |
| 硬件余量 | RAM<1.5G 或 存储<500M | 2G/8G 档 | ≥3G/16G |
| 系统现代度 | SDK<26 | 26–29 | ≥30 |
| 广告侵入度 | 开机+桌面+贴片 | 两类 | 仅一类或可关 |
| 可回滚性 | 无固件包 | 有官方包 | 官方包+已验证恢复 |
| 定制锁定 | 运营商强校验 | 品牌轻定制 | 公版/开放 |

- **≥9 分**：A 级，值得投入。
- **6–8 分**：B 级，做应用层，别碰固件。
- **≤5 分**：C/D 级，外围方案或换机。

评分卡的用途是**同类设备横向比较与投入决策**，不是否决低配设备的工具。低分设备只要 G1（ADB 可接管）成立，仍走 §2.5 路径。

### 2.4 明确"不可优化"的硬性判据

命中任一，直接判 D，停止投入：

- 运营商 IPTV 定制机且鉴权走硬件证书——拆机改系统会丢直播授权，且无法恢复。
- 型号无法确认到 `ro.product.device` 级——任何刷机包都可能刷错分区。
- 已过保但为唯一电视来源，且无第二台备用设备。
- 系统为封闭自研（非 Android，如部分自研 OS）——本手册全部失效。
- 目标只是"看 4K 高码率"但硬件解码能力不足——软件优化无法弥补。

### 2.5 低配设备（RAM<1GB / SDK<21）不是不可优化

常见误判：看到 "Android 4.4 + 512MB RAM" 就判死。**实测反例**（创维 Q0108，同一台设备）：

| 指标 | 优化前 | 优化后 | 手段 |
|---|---|---|---|
| 空闲内存 | 55 MB | 226 MB | block 原桌面 + 换极简桌面 + 禁 15 个后台包 |
| 桌面占用 | 82 MB | 26 MB | 自建 32KB 级轻桌面 |
| 开机落点 | 原桌面（广告位） | 极简桌面 | `pm block` 原桌面 |
| 崩溃 | 选择器必崩 | 0 | 消除多候选 |

低配设备的可优化上限确实低，但**盘活的绝对值很大**（内存 ×4）。这类设备走另一套路径：`pm block` 替代 `disable`、包名前缀过白名单、自建极简桌面、放弃所有 2020 年后编译的应用。

**判定改为**：G4 不达标 ≠ D 级。先确认能否 ADB 接管（G1），能接管就有 100–200MB 的操作空间；不能接管才是 C/D。完整路径见 `references/lowend-android.md`。

---

## 3. 优化方向分类

按"风险从低到高"排序。执行时**严格自上而下**，前一层稳定后再进下一层。

| # | 方向 | 适用条件 | 主要收益 | 风险 | 回滚方式 |
|---|---|---|---|---|---|
| 1 | 广告与追踪拦截 | 全部等级 | 去开机/贴片/推送广告 | 低 | 恢复设置 / 换 DNS |
| 2 | 网络与 DNS 配置 | 全部等级（SDK≥28 用 Private DNS） | 全域去广告、加速解析 | 低 | 设回 `off` |
| 3 | 应用层瘦身 | B 及以上 | 减后台、减内存、减弹窗 | 中低 | `install-existing` |
| 4 | 启动器替换 | B 及以上 | 去桌面广告位、可自定义 | 中（遥控键位） | 设回原 launcher |
| 5 | 性能与内存调优 | A/B | 缓解卡顿、缩短开机 | 中 | 恢复动画/进程参数 |
| 6 | 输入与 CEC | A/B | 单遥控器控制、键位顺手 | 中低 | 重配遥控 / 恢复设置 |
| 7 | 系统服务治理 | 仅 A（需 root） | 彻底断开广告 SDK | 高 | 解冻服务 / 还原分区 |
| 8 | 固件层（OTA/第三方/root） | 仅 A 且 G3/G5 通过 | 根治、去厂商预装 | 极高（可变砖） | 官方包线刷 |

**方向选择规则**：

- 目标只是"去广告" → 只做 1+2，收益已达 80%，风险最低。不要为了去广告去 root。
- 目标是"卡顿" → 先做 3+5，再看 `top` 输出是否仍被系统进程占满，才考虑 7。
- 目标是"开机广告" → 1（停用广告服务）+ 4（换桌面）通常足够；仍不行才考虑 7。
- 目标是"纯净系统" → 8，但必须先能拿到官方固件包作为后悔药。

---

## 4. 各方向处理方案与操作步骤

每个方向统一四段式：**前置 → 操作 → 验证 → 回滚**。验证不过不进下一步。

### 4.1 方向 1：广告与追踪拦截（应用层）

**前置**：G1 通过（ADB 可用）。目标包名已通过 §4.3 的枚举确认。

**操作**：

```bash
# 1) 全量导出包清单（留档，回滚依据）
adb shell pm list packages -f > packages-before.txt
adb shell pm list packages -d > disabled-before.txt

# 2) 枚举候选广告包（按关键字过滤，人工确认后再动）
adb shell pm list packages | grep -Ei 'advert|ads|promot|push|banner|market|game|shop|recommend'

# 3) 查包详情，确认是广告 SDK 而非系统组件
adb shell dumpsys package <pkg> | grep -E 'versionName|firstInstallTime|pkgFlags|sharedUser'

# 4) 先停用（可秒恢复），不直接卸载
adb shell pm disable-user --user 0 <pkg>

# 5) 观察 24–72h 无异常，再卸载到用户 0（仍可恢复）
adb shell pm uninstall --user 0 <pkg>
```

`--user 0` 是关键：它移除当前用户可见性，**不删除系统分区文件**，因此可逆。除此之外的删除方式（不带 `--user 0` 的 `pm uninstall`、有 root 时 `rm` APK）都是分区级破坏，只能线刷恢复。

**验证**：

```bash
adb shell pm list packages -d            # 确认已停用列表
adb shell dumpsys activity processes | grep <pkg>   # 无残留进程
# 人工验证：冷启动开机广告是否消失、桌面是否有空位/白块
```

**回滚**：

```bash
adb shell pm enable <pkg>
adb shell cmd package install-existing <pkg>
```

**`pm disable` 失败时（定制固件常见）**：

```
SecurityException: Permission Denial: attempt to change component state
from uid=2000, package uid=1000
```

说明厂商从 `platform.xml` 删掉了 shell 的 `CHANGE_COMPONENT_ENABLED_STATE`。此时不要反复试、不要提权，改用 **`pm block`**：

```bash
adb shell pm block <pkg>        # 比 disable 更彻底，写 packages.xml，重启保持
adb shell pm unblock <pkg>      # 回滚
```

`pm block` 让包从系统查询中消失并强制停止，不受该权限限制。API<21 上它是主力手段。详见 `references/lowend-android.md` §2。

**注意版本边界**：`cmd package install-existing` 是 API 21+。API<21 上卸载第三方应用只能靠重装 APK，所以**动手前必须备份 APK**。系统应用 `pm uninstall` 只卸更新层，回退到 `/system/app` 原版，`block` 后才彻底不启动。

**必守清单**（这些包停用会导致黑屏、无网、遥控失灵、DRM 失效，见 `references/package-lists.md`）：`systemui`、`settings`、当前唯一的 `launcher`、`inputmethod*`、`bluetooth`、`providers.*`、`widevine`/`drm`、`phone`（运营商盒子）、`shell`。

### 4.2 方向 2：网络与 DNS 配置

**前置**：网络可达；SDK≥28 用 Private DNS，SDK<28 需 root 改 hosts 或在路由器层做。

**操作（Private DNS，推荐）**：

```bash
# 先测目标 DoH 是否可达，不通会导致整机断网
adb shell ping -c 2 dns.adguard-dns.com

adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier dns.adguard-dns.com
adb shell settings put global private_dns_mode opportunistic   # 或仅机会式（不强制）
```

**操作（路由器层，最安全，覆盖全屋）**：把 DHCP 下发的 DNS 指向自建 AdGuard Home / Pi-hole，盒子上什么都不用改。具体见 `references/adblock-config.md`。

**操作（静态 IP + 指定 DNS，防 DHCP 变更）**：

```bash
adb shell settings list global | grep -i dhcp       # 先看现状，勿盲改
# 静态 IP 一般在厂商 UI 里改，命令方式因 ROM 而异，优先走 UI
```

**验证**：

```bash
adb shell settings get global private_dns_mode
adb shell nslookup doubleclick.net             # 应被拦截/无解析
adb shell dumpsys connectivity | grep -i dns   # 查看实际生效的 DNS
```

**回滚**：

```bash
adb shell settings put global private_dns_mode off
```

### 4.3 方向 3：应用层瘦身

**前置**：已完成 `packages-before.txt` 留档。

**操作顺序（务必按此顺序，不要跳）**：

```bash
# A. 第三方应用：先看体积与最后使用时间
adb shell pm list packages -3
adb shell dumpsys package <pkg> | grep -E 'lastUpdateTime|firstInstallTime'

# B. 系统预装：区分"可停用"与"不可动"
adb shell pm list packages -s
# 逐个确认用途，不认识的先查再动，不要图快批量停用

# C. 分三批执行，每批 ≤10 个，每批后重启验证
adb shell pm disable-user --user 0 <pkg1> <pkg2> ...
adb reboot
```

**批量工具的取舍**：UAD（Universal Android Debloater）能按品牌推荐清单批量停用，效率高，但**推荐清单是社区经验，不等于你的固件安全**。用它时选 `Recommended` 级而非 `Advanced`/`Expert` 级，且首次只执行前 5 项、重启验证。

**验证**：

```bash
adb shell dumpsys meminfo | head -20        # 可用内存应上升
adb shell pm list packages | wc -l          # 数量下降
# 人工验证：能开机、能联网、遥控可用、能装应用、能播视频（含 DRM 内容）
```

**回滚**：`adb shell cmd package install-existing <pkg>`。**注意**：`install-existing` 只对 `--user 0` 卸载有效；如果用了 root 删 APK，只能靠还原备份或线刷。

### 4.4 方向 4：启动器替换

**前置**：已装好目标桌面（Projectivy Launcher / ATV Launcher / 当贝桌面等）；原 launcher 包名已记录。

**操作**：

```bash
# 1) 记录原桌面
adb shell cmd package resolve-activity --brief -c android.intent.category.HOME

# 2) 安装新桌面后，查其可启动组件
adb shell cmd package resolve-activity --brief -c android.intent.category.HOME -p <newlauncher.pkg>

# 3) 设为默认 Home（仅 API21+ 且 cmd 存在时可用）
adb shell cmd package set-home-activity <newlauncher.pkg>/<activity>

# 4) 停用原桌面广告位（可选，先确认新桌面 Home 键正常）
adb shell pm disable-user --user 0 <old.launcher.pkg>
```

**接管路径按可用性三选一**（顺序不能乱）：

| 条件 | 路径 |
|---|---|
| `cmd package` 存在（API21+） | 上面第 3 步直接设 |
| `cmd` 不存在，RAM ≥ 1GB | 按 Home 键，在系统弹窗里选新桌面 + 勾"始终" |
| `cmd` 不存在，且按 Home 会黑屏/闪回（低内存机常见） | **先确认新桌面能手动启动**，再 `pm block <old.launcher.pkg>`，让 HOME 唯一候选被系统直接拉起 |

第三条的机制：选择器 `ResolverActivity` 在低内存机上会崩，所以不能指望"选始终"。`pm block` 原桌面后候选只剩一个，系统跳过选择直接启动（日志出现 `from pid 0`）。

**block 前的硬性验证**：`am start` 新桌面 → `mResumedActivity` 是它 → `logcat` 无 `FATAL EXCEPTION`。三步都过才 block，否则黑屏且遥控救不回。详见 `references/lowend-android.md` §3。

**另外**：新装的包处于 `stopped` 状态，收不到 `BOOT_COMPLETED`。必须先 `am start` 一次解除，否则"开机自启"永远不生效。

**遥控键位问题**：部分国产盒子 Home 键被厂商硬绑定（写死在 frameworks 或专用按键服务里），换桌面后按 Home 会跳回原桌面。此时**不要停用原桌面**，否则按 Home 会黑屏。判断方法：换完后按 Home 键 3 次，看是否稳定回到新桌面，稳定才继续。

**验证**：Home 键 3 次、重启 1 次、电源键待机/唤醒 1 次，均正常。

**回滚**：

```bash
adb shell pm enable <old.launcher.pkg>
adb shell cmd package set-home-activity <old.launcher.pkg>/<activity>
```

### 4.5 方向 5：性能与内存调优

**前置**：已采集基线（开机时间、可用内存、`top` 前 10 进程）。没有基线就没有收益证明。

**操作（保守档，全部可逆）**：

```bash
# 缩短/关闭动画（TV 上观感提升明显）
adb shell settings put global window_animation_scale 0.5
adb shell settings put global transition_animation_scale 0.5
adb shell settings put global animator_duration_scale 0.5

# 查看而非盲改：当前缓存进程上限
adb shell settings get global activity_manager_constants

# 清理各应用缓存（安全，不动数据）
adb shell pm trim-caches 2048M
```

**谨慎档（改了可能引发应用被杀/后台服务失效，A 级设备才做）**：

```bash
# 限制缓存进程数，缓解内存压力；不同 ROM 支持度不同，改前记录原值
adb shell settings get global activity_manager_constants
adb shell settings put global activity_manager_constants max_cached_processes=8
```

**不要做的"优化"**（伪优化，危害大于收益）：

| 伪优化 | 实测后果 |
|---|---|
| 定时杀后台 / 装内存清理 App | 冷启动 5.4s vs 热启动 2.0s，每次多等 3.4 秒。**"优化后更卡"的头号原因** |
| 用 `MemFree` 判断内存健康 | `MemFree` 不含 page cache，阈值判断必然误触发，会把常用应用杀掉 |
| 改 `vm.swappiness` | TV 无 swap，无效果 |
| 改 CPU governor | 多数 TV 内核不开放，强行改易过热降频 |

内存指标用 `MemAvailable`（内核 ≥3.14），老内核用 `MemFree + Cached` 近似。详见 `references/lowend-android.md` §6。

**验证**：同样操作路径下重测开机时间与可用内存，对比基线。3 次取中位数。

**回滚**：

```bash
adb shell settings put global window_animation_scale 1.0
adb shell settings put global transition_animation_scale 1.0
adb shell settings put global animator_duration_scale 1.0
adb shell settings delete global activity_manager_constants
```

### 4.6 方向 6：输入与 CEC

**前置**：确认遥控是红外还是蓝牙（`adb shell dumpsys bluetooth_manager | grep -i remote`）。

**操作**：

- 蓝牙遥控失配：`adb shell settings` 改不动，必须走 UI 重新配对；配不上时用 USB 键盘/鼠标临时接管，或用 `scrcpy` 完全绕过遥控。
- HDMI-CEC：设置里开"设备联动/一键开机"，让电视遥控接管盒子；不同品牌命名不同（CEC / Anynet+ / BRAVIA Sync / Simplink）。
- 键位映射：需 root 或专用按键映射 App，属高风险项，非必要不做。

**验证**：断电重插后，遥控可用、开机联动生效。

**回滚**：关闭 CEC 开关、UI 内移除蓝牙配对重配。

### 4.7 方向 7：系统服务治理（仅 A 级，需 root）

**前置**：G2 已确认有 root；已用 `su` 验证；已做分区级备份（至少 `/system` 可还原路径或官方包在手）。

**操作原则**：**冻结优于删除**。优先用 `pm disable` / `pm suspend`，其次 `Magisk` 模块屏蔽，最后才考虑改分区。

```bash
adb shell su -c 'pm disable-user --user 0 <pkg>'
adb shell su -c 'mount -o rw,remount /system'   # 仅在确需改分区时
```

**不要做的事**：删 `/system/app` 下不认识的 APK、改 `build.prop` 中的 `ro.product.device`、关 `zygote`/`servicemanager` 相关服务。

**验证**：完整重启 3 次均正常（root 级改动有时首次正常、二次启动循环）。

**回滚**：`pm enable`；分区改动必须能通过官方包线刷还原，否则不要动手。

### 4.8 方向 8：固件层

**前置（缺一不可）**：`ro.product.device` 已精确确认 + 官方/可信固件包已下载 + 线刷工具与驱动可用 + 设备可弃风险已接受。

**操作原则**：

1. **先 OTA 到最新官方版**再评估。很多老固件的广告位在新版已被官方移除，刷第三方反而引入新问题。
2. 第三方固件只从项目官方发布页取，**不使用来历不明的"纯净版"**（大量此类包内置挖矿与后门）。
3. 刷机前记录：`ro.build.fingerprint`、分区表、原厂固件下载链接。
4. 线刷过程中不断电、不拔线。

**验证**：开机 → 联网 → 遥控 → 播放 DRM 内容 → OTA 状态符合预期（是否要禁更新）。

**回滚**：官方固件线刷。这是唯一可靠回滚方式——**没有官方包就不要刷**。

---

## 5. 去广告操作与配置说明

广告不是一处，是五层。按层拦截，从成本最低的开始，能停在低层就不要进高层。

### 5.1 五层拦截模型

| 层 | 作用范围 | 手段 | 覆盖广告类型 | 风险 | 见效速度 |
|---|---|---|---|---|---|
| **L0 手动跳过** | 单次 | 按遥控器 OK 键 / 找"跳过"提示 | 开屏、投屏前贴片 | 零 | 立即 |
| **L1 域名层** | 全屋所有设备 | AdGuard Home / Pi-hole / 路由器 DNS | 贴片、开屏、信息流、上报 | 极低 | 立即 |
| **L2 应用层** | 单设备 | 停用广告 SDK 包、关个性化推荐开关 | 弹窗、推送、推荐位 | 低 | 重启后 |
| **L3 系统层** | 单设备（需 root） | 冻结广告服务、改 hosts、屏蔽开机广告服务 | 开机广告、待机广告 | 中高 | 重启后 |
| **L4 内容层** | 单应用 | 换客户端（SmartTube / BILI-TV 等）、换源 | 播放前/中插播 | 低 | 立即 |

**优先级**：L0 → L1 → L2 → L4 →（必要时）L3。**L1 能解决 60% 以上，且零风险**，绝大多数人做到这就够了。

**L0 必须先试**：广告页常自带"按 OK 键跳过"。实测按一次后，广告接口返回空素材（`adBean size 0`），后续多次投屏不再出现广告。**先按一下遥控器，再决定要不要动系统。**

### 5.2 L1 域名层配置

**方案 A：路由器 DNS 指向 AdGuard Home（推荐）**

1. 部署 AdGuard Home（Docker / OpenWrt 插件 / 独立小主机）。
2. 路由器 DHCP 的 DNS 服务器改为 AdGuard Home 的 IP（**不要改 WAN 侧 DNS**）。
3. 盒子重连 Wi-Fi 或重启，`adb shell dumpsys connectivity | grep -i dns` 确认已指向。
4. 在 AdGuard Home 的查询日志里确认盒子的请求在被处理。

**方案 B：盒子内置 Private DNS（单设备生效）**

见 §4.2。只影响该设备，适合不想动全家网络的场景。

**方案 C：hosts（需 root）**

```bash
adb shell su -c 'mount -o rw,remount /system'
adb shell su -c 'cat /data/local/tmp/hosts > /system/etc/hosts'
adb shell su -c 'mount -o ro,remount /system'
```

hosts 只能精确匹配域名，对 CDN 与 IP 直连无效；**OTA 升级会覆盖**，不推荐作为长期方案。

**广告域一定有备用域**。实测某投屏 App 同时用 `adeng.hpplay.cn` 和 `adeng.lebo.com.cn`，拦了前者就切后者——只拦一个等于没拦。同样，广告域与业务域常同源（同一 `hpplay.cn` 主域下既有广告引擎也有设备发现），**逐个精确拦，绝不用通配符封整域**。域名分层与实测清单见 `references/lowend-android.md` §9.2。

**DNS 配置的三个必须验证项**（任一不过就回滚）：

1. 盒子能正常解析并播放视频（DNS 误杀 CDN 会导致全线加载失败）。
2. 应用商店能正常更新（部分商店域名与广告域同名段）。
3. 系统 OTA 检查不报错（若你仍需要更新能力）。

具体域名清单、黑白名单策略、DoH/DoT 端点见 `references/adblock-config.md`。

### 5.3 L2 应用层配置

1. **枚举**：`adb shell pm list packages | grep -Ei 'advert|ads|promot|push|recommend'`。
2. **确认**：`dumpsys package` 看包签名与 `sharedUser`，确认是独立广告 SDK 而非系统组件。
3. **停用**：`pm disable-user --user 0 <pkg>`。
4. **UI 侧同步关闭**：设置里的"个性化推荐""用户体验改进计划""广告标识符重置"——这些开关常与包停用**互不覆盖**，两处都要关。
5. **重启验证**：冷启动一次，看开机广告与桌面推荐位。

### 5.4 L3 系统层配置（仅 A 级）

- 开机广告通常由**独立服务**驱动，与桌面广告分离。先定位：`adb shell dumpsys activity services | grep -i ad`。
- 冻结服务后若出现黑屏数十秒、开机变慢，说明该服务兼做初始化，立即恢复。
- 部分厂商广告有**签名校验 + 远程开关**，本地冻结会在下次联网时被重新拉起；此时只能靠 L1 域名层掐断其配置下发域名。

### 5.5 副作用与规避

| 操作 | 典型副作用 | 规避 |
|---|---|---|
| 停用广告包 | 桌面留白块、某些按钮点击无响应 | 只停用确认过的包；先停用观察再卸载 |
| DNS 拦截 | 视频加载失败、商店更新报错 | 保留白名单，先观察日志再加规则 |
| 换桌面 | Home 键跳回原桌面 / 黑屏 | 不停用原桌面直到键位验证通过 |
| 停用系统更新 | 失去安全更新 | 记录版本，手动周期性检查官方公告 |
| 卸载"疑似无用"系统包 | 无网、无声音、遥控失灵、DRM 黑屏 | 严守 §4.1 必守清单，分批执行 |

---

## 6. 验收与回滚

### 6.1 验收清单（全部通过才算完成）

| 项 | 验证方式 | 通过标准 |
|---|---|---|
| 可开机 | 断电重插 | 正常进桌面，无卡 logo、无无限重启 |
| 可联网 | 打开在线视频 | 30s 内起播 |
| 遥控可用 | 方向/确认/返回/Home/电源 各按 3 次 | 全部响应，Home 稳定回目标桌面 |
| 可装应用 | 装一个测试 APK | 安装成功且能启动 |
| DRM 可播 | 播一个受版权保护的内容 | 不黑屏、不报错 |
| 广告已减 | 冷启动 + 桌面浏览 | 目标广告位消失，无新增异常 |
| 可回滚 | 按回滚命令实执行 1 项 | 恢复成功 |

### 6.2 观察期

- **24h**：日常使用无异常（重点看是否偶发重启、遥控失灵）。
- **72h**：跨过一次待机/唤醒、一次长时间待机。
- **7d**：无自动恢复的广告（说明未被远程重新下发）。

观察期内出问题，**立即回滚最后一步**，不要"再试试别的改动"叠加变量。

### 6.3 回滚优先级

1. `pm enable` / `install-existing`（秒级，先试这个）
2. `settings put` 恢复原值（秒级）
3. 恢复默认桌面 / DNS 关闭（分钟级）
4. 官方固件线刷（小时级，最后手段）

---

## 7. 可借鉴的开源项目与方案

只列确知存在的项目，用途写清，不做功能夸大。

| 项目 | 用途 | 在本手册中的位置 |
|---|---|---|
| `Genymobile/scrcpy` | USB/TCP 投屏 + 键鼠接管，免遥控排查 | §4.6 遥控失灵时的替代输入 |
| `0x192/universal-android-debloater` | 图形化批量停用预装包，含品牌推荐清单 | §4.3 批量瘦身（只用 Recommended 级） |
| `AdguardTeam/AdGuardHome` | 自建 DNS 拦截，带查询日志与白名单 | §5.2 L1 层主力方案 |
| `pi-hole/pi-hole` | 同上，轻量替代 | §5.2 L1 层备选 |
| `topjohnwu/Magisk` | 系统级 root 与模块管理（不破坏分区可逆） | §4.7 方向 7 的前置能力 |
| `MuntashirAkon/AppManager` | 应用级冻结/权限/组件管理，部分功能免 root | §4.3 / §5.3 精细化管理 |
| `termux/termux-app` | 手机端直接跑 adb，无需电脑 | 现场排障 |
| `yuliskov/SmartTube` | Android TV 端 YouTube 第三方客户端，无广告 | §5.1 L4 内容层 |
| `k1moj1s/BILI-TV` | B 站第三方 TV 客户端，明确提供 API19 / armeabi-v7a 包 | §5.1 L4；低配老盒子的少数可用选择 |
| `louis49/androidtv`（python-androidtv） | 局域网电视控制/状态读取，脚本化 | §1.2 发现与自动化 |
| `home-assistant/core`（androidtv 集成） | 把电视接入自动化，做状态联动 | 长期维护场景 |

**借鉴原则**：

- 抄**方法论**（分层拦截、冻结优于删除、先停用后卸载），不抄**未经你设备验证的清单**。
- 社区清单的价值是"缩小候选范围"，判定仍以 `dumpsys` 实测为准。
- 影视聚合类项目（各类 TVBox 分支）涉及内容合规，本手册不提供配置指导。

---

## 附录 A：命令速查

```bash
# 连接
adb connect <ip>:5555 ; adb devices -l ; adb disconnect <ip>:5555

# 身份
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.type ; adb shell getprop ro.debuggable

# 包管理
adb shell pm list packages -3            # 第三方
adb shell pm list packages -s            # 系统
adb shell pm list packages -d            # 已停用
adb shell pm list packages -f <pkg>      # 安装路径
adb shell dumpsys package <pkg>          # 详情
adb shell pm disable-user --user 0 <pkg> # 停用（可逆）
adb shell pm enable <pkg>                # 恢复
adb shell pm uninstall --user 0 <pkg>    # 卸载到用户 0（可逆）
adb shell cmd package install-existing <pkg>   # 恢复卸载
adb shell pm trim-caches 2048M           # 清缓存

# 桌面
adb shell cmd package resolve-activity --brief -c android.intent.category.HOME
adb shell cmd package set-home-activity <pkg>/<activity>

# 系统设置
adb shell settings get/put/delete global <key>
adb shell settings list global | grep -i dns

# 诊断
adb shell dumpsys meminfo | head -20
adb shell top -n 1 -m 10 -o %CPU,RES,CMDLINE
adb shell df -h /data
adb shell logcat -d -b crash | tail -50
adb shell dumpsys activity services | grep -i ad

# 降级 / 兼容（API≤19、权限被剥）
adb shell pm block <pkg>                 # disable 失效时的替代
adb shell pm unblock <pkg>
adb shell pm 2>&1 | head -40             # 探测支持哪些子命令
adb shell cat /system/etc/permissions/platform.xml | grep -c 'uid="shell"'
adb shell am start -n <pkg>/<activity>   # 解除新装应用的 stopped 状态
aapt dump badging app.apk | grep -E "package:|sdkVersion|native-code"   # 装前预检
```

## 附录 B：危险操作红线

| 操作 | 后果 | 是否允许 |
|---|---|---|
| `pm uninstall` 不带 `--user 0`（系统应用） | 分区级移除，只能线刷恢复 | 禁止 |
| 删 `/system/app` 下任意 APK | 可能无法开机 | 禁止（用 disable） |
| 改 `build.prop` 的 `ro.product.device` | OTA 变砖、刷机包错配 | 禁止 |
| 停用唯一 launcher / systemui / inputmethod | 黑屏或无法操作 | 禁止 |
| 停用 DRM（widevine 等） | 付费内容全黑屏 | 禁止 |
| 使用来源不明的"纯净固件" | 后门、挖矿、隐私泄露 | 禁止 |
| 在他人网络扫描/接管设备 | 违法 | 禁止 |

## 附录 C：常见故障对照

| 症状 | 最可能原因 | 处置 |
|---|---|---|
| `adb connect` 超时 | 不同子网 / AP 隔离 / 5555 未开 | 检查网段、关 AP 隔离、UI 开 ADB |
| `unauthorized` | 电视端未点允许 | 电视上确认弹窗；`adb kill-server` 后重连 |
| `offline` | adbd 版本不匹配 | 升级 platform-tools，重连 |
| 改完无法开机 | 停了关键系统包 | 恢复出厂（部分机型）或线刷官方包 |
| 遥控完全失灵 | 蓝牙配对丢失 / 输入法被停 | 插 USB 键鼠接管，重配蓝牙 |
| 视频全部加载失败 | DNS 误杀 CDN | 立即 `private_dns_mode off` 或恢复路由器 DNS |
| 播放付费内容黑屏 | DRM 组件被停用 | `install-existing` 恢复 widevine 相关包 |
| Home 键跳回原桌面 | 厂商硬绑定 | 启用原桌面，仅用新桌面作为应用启动 |
| 优化后广告回来了 | 远程配置重新下发 | 加 L1 域名层拦截其配置域名 |
| OTA 被反复弹窗 | 更新包被停用但通知服务仍在 | 停用通知服务，或接受弹窗 |
| 卸载的广告包自己回来了 | OTA 把它推回 | `pm block` 掉 OTA 包（lowend §2.3） |
| 改完重启被还原 | 厂商白名单由服务器下发覆盖 | 用包名前缀通过白名单（lowend §4.3） |
| 按 Home 黑屏 / 闪回 | 选择器在低内存机上崩溃 | 先验证新桌面能起，再 `pm block` 原桌面 |
| 新桌面开机不自启 | 包处于 stopped 状态 | `am start` 一次解除 |
| 装上就崩 `NoClassDefFoundError: android.system.Os` | 加固壳用了高版本 API，minSdk 标称是假的 | 放弃该包 |
| `INSTALL_FAILED_OLDER_SDK` | minSdk > 设备 SDK | 换包，别折腾降级 |
| 手机搜不到投屏设备 | SSDP 组播绑错网卡 / 开机时 WiFi 未就绪 | 绑 `wlan0`、监听 IP 变化重建（lowend §7） |
| 优化后比之前更卡 | 定时杀后台 / 用 `MemFree` 判内存 | 撤掉清理逻辑（lowend §6） |
