# 品牌 / 平台适配矩阵

按 §1.4 拿到 `ro.product.brand` + `ro.product.model` 后查此表，确定 ADB 开启路径与可执行方向。

**使用警告**：品牌 OEM 会随固件版本改 UI 路径与包名。下表给的是**路径模式**，实际以设备上的菜单为准。任何"包名清单"在使用前必须用 `pm list packages` 实测校验。

---

## 1. ADB 开启路径（按品牌）

通用套路：**设置 → 关于/系统信息 → 版本号（或产品型号）连点 7 次 → 返回 → 开发者选项 → 开启 USB/网络调试**。

| 品牌 / 系列 | 路径特征 | 常见卡点 |
|---|---|---|
| 小米 / Redmi 电视、小米盒子 | 设置 → 关于 → 产品型号连点 7 次；再进"账号与安全"开 ADB | 需登录小米账号；网络调试可能要求同账号绑定 |
| 当贝盒子 | 设置 → 关于 → 版本号连点；开发者选项内有"无线调试" | 部分型号默认已开 5555 |
| 创维 / 酷开 | 设置 → 关于本机 → 版本号连点 | 部分机型 ADB 入口在工厂菜单（遥控器按"菜单+音量-"）。**实测 Q0101/Q0108（企鹅极光 T1 青春版）：ADB 已开且直连 5555 可用，但 `service.adb.tcp.port` 是临时属性，`persist.adb.tcp.port` 写入被拒 → 重启即失联** |
| 海信 | 设置 → 关于 → 版本号连点 7 次 | 新版固件可能隐藏"开发者选项"，需在"系统 → 高级"下找 |
| TCL / 雷鸟 | 设置 → 系统 → 关于 → 版本号连点 | 雷鸟机型 ADB 需在"更多设置"内 |
| 华为智慧屏 | 设置 → 关于 → 版本号连点 → 开发者选项 | HarmonyOS 版本对 adb 命令集有限制，`pm` 部分子命令不可用 |
| 长虹 / 康佳 | 设置 → 系统信息 → 版本号连点 | 老机型需通过 U 盘升级包开 ADB |
| 运营商盒子（移动魔百和 / 电信天翼 / 联通） | 通常**无公开 ADB 入口** | 需工厂菜单密码或特定 U 盘脚本；风险最高，见 §3 |
| 外贸盒子（Amlogic S905/S922、Rockchip RK35xx） | 多数默认开 5555，或刷机后自带 | 原厂固件常带广告与后门，刷开源 ATV 反而是首选方案 |
| 投影（极米 / 坚果 / 当贝投影） | 同上，走"关于 → 版本号" | 部分型号 ADB 端口非 5555，需扫描确认 |

**开启后自检**：

```bash
adb connect <ip>:5555
adb devices -l
adb shell getprop ro.product.model    # 能取到值 = 通道打通
```

---

## 2. 平台 / 芯片 → 可刷性判断

| 平台 | 常见机型 | BL 解锁 | 第三方固件生态 | 刷机风险 |
|---|---|---|---|---|
| Amlogic S905X/X2/X3/X4 | 外贸盒子、部分投影 | 多数可（USB Burning Tool） | 丰富（开源 ATV 镜像多） | 中（有官方烧录工具，可救） |
| Amlogic S922X | 高端外贸盒 | 可 | 中等 | 中 |
| Rockchip RK3328/RK3399/RK3566 | 外贸盒、部分一体机 | 可（maskrom 模式） | 中等 | 中 |
| 海思 Hi3798（运营商） | 魔百和等 | 强锁定 | 极少 | 高（易彻底变砖） |
| 联发科 MT5xxx（电视主板） | 品牌电视 | 通常不可 | 少 | 高 |
| 晶晨定制 + 厂商签名校验 | 国产品牌盒 | 视厂商 | 少 | 高 |

**判断规则**：没有厂商官方线刷工具 + 没有可下载的原厂固件 → **禁止刷机**，无论社区教程多热闹。

---

## 3. 运营商定制机的特殊处理

特征识别：

```bash
adb shell pm list packages | grep -Ei 'iptv|ott|auth|epg|multicast|telecom|unicom|cmcc|chinanet'
adb shell getprop | grep -Ei 'operator|carrier|province'
```

**实测厂商包名线索**（用于快速判断体系归属，不用于判定能否停用）：

| 前缀 | 厂商 | 常见用途 |
|---|---|---|
| `com.skyworthdigital.*` | 创维 | 桌面、设置、广告投放、统计、OTA、按键设置 |
| `com.tianci.*` | 创维（天赐） | 广告、升级 |
| `com.mipt.*` | 创维（应用商店） | 商店主进程 + 常捆绑广告推送服务（一个包两个进程） |
| `com.hpplay.*` | 乐播 | 投屏接收端（广告与业务同源） |
| `com.xiaopaitech.*` | 小湃 | 投屏 SDK / Cast+ |

风险清单：

| 风险 | 说明 | 后果 |
|---|---|---|
| 直播鉴权绑硬件 | IPTV 账号与 MAC/证书绑定 | 改系统后直播永久失效，且无法自助恢复 |
| 强制 OTA 回滚 | 联网即被推送原厂固件 | 优化成果被覆盖 |
| 无官方固件包 | 厂商不对外提供 | 变砖后只能报修 |
| 保修条款 | 拆改即失保 | 无法免费维修 |

**结论**：运营商盒子默认按 **C 级**处理（仅路由器侧 DNS 拦截），不做系统层操作。除非该设备已非唯一收视来源且用户明确接受损失。

---

## 4. 系统版本 → 能力边界

| SDK | Android | 关键能力差异 | 对本手册的影响 |
|---|---|---|---|
| < 26 | ≤ 7.1 | 无 Private DNS、**无 `cmd package`**、`pm disable` 可能被剥权限 | 走 `pm block` 路线（见 `lowend-android.md` §2）；2020 年后编译的客户端基本装不上 |
| 26–27 | 8.x | 有 `pm disable-user`、无 Private DNS | 广告包停用可用；DNS 走路由器 |
| 28–29 | 9–10 | 有 Private DNS（DoT/DoH） | §4.2 全量可用 |
| 30+ | 11+ | 无线调试带配对码、分区更严格 | `adb pair` 流程；系统分区几乎不可写 |

`adb pair`（Android 11+ 部分设备）：

```bash
adb pair <ip>:<pair_port>     # 配对码在电视"无线调试"界面
adb connect <ip>:5555
```

注：多数 TV 的"网络调试"仍是 5555 直连，不需要配对；只有明确显示配对码时才走 `adb pair`。

---

## 5. 快速判级脚本（可直接跑）

```bash
#!/usr/bin/env bash
# 用法: ./grade.sh 192.168.1.50
IP="${1:?need ip}"
adb connect "$IP:5555" >/dev/null 2>&1

g() { adb -s "$IP:5555" shell getprop "$1" 2>/dev/null | tr -d '\r'; }

MODEL=$(g ro.product.model); BRAND=$(g ro.product.brand)
SDK=$(g ro.build.version.sdk); BTYPE=$(g ro.build.type)
DBG=$(g ro.debuggable); DEV=$(g ro.product.device)
MEM=$(adb -s "$IP:5555" shell cat /proc/meminfo 2>/dev/null | awk '/MemTotal/{print int($2/1024)}')

echo "brand=$BRAND model=$MODEL device=$DEV sdk=$SDK build=$BTYPE debuggable=$DBG ram=${MEM}MB"

SCORE=0
if [ "$DBG" = "1" ] || [ "$BTYPE" = "userdebug" ]; then
  SCORE=$((SCORE+2))
else
  SCORE=$((SCORE+1))
fi
if [ "${MEM:-0}" -ge 3000 ]; then SCORE=$((SCORE+2))
elif [ "${MEM:-0}" -ge 1900 ]; then SCORE=$((SCORE+1)); fi
if [ "${SDK:-0}" -ge 30 ]; then SCORE=$((SCORE+2))
elif [ "${SDK:-0}" -ge 26 ]; then SCORE=$((SCORE+1)); fi
echo "openness/hw/modern subscore=$SCORE  (满分6，另3项需人工判：广告侵入度/可回滚性/定制锁定)"
```

脚本只做机械判定，**最终评级必须人工补齐 §2.3 的后三项**（广告侵入度、可回滚性、定制锁定）——这三项无法从 `getprop` 读出。
