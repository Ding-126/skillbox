# 去广告配置手册（DNS / 域名层）

核心方法只有一句：**不要抄别人的域名清单，从你自己设备的 DNS 查询日志里抓。**

原因：电视广告域名高度本地化、随固件版本变化，社区清单命中率通常不到一半，还会误杀 CDN。抓日志 10 分钟，比找清单 10 小时有效。

---

## 1. 三层落地方式对比

| 方式 | 生效范围 | 前置 | 可观测性 | 推荐度 |
|---|---|---|---|---|
| 路由器 DHCP 指向自建 DNS | 全屋 | 一台常开设备跑 AdGuard Home / Pi-hole | 强（有查询日志） | ★★★★★ |
| 盒子 Private DNS（DoT/DoH） | 单设备 | SDK≥28 | 弱（看不到日志） | ★★★ |
| hosts / 改 DNS 服务器 IP | 单设备 | root 或 UI 可改 | 无 | ★ |

---

## 2. 方案 A：AdGuard Home（推荐）

### 2.1 部署

```bash
docker run -d --name adguardhome \
  -v /opt/adguardhome/work:/opt/adguardhome/work \
  -v /opt/adguardhome/conf:/opt/adguardhome/conf \
  -p 53:53/tcp -p 53:53/udp \
  -p 3000:3000/tcp \
  --restart unless-stopped \
  adguard/adguardhome
```

浏览器打开 `http://<host>:3000` 完成初始化（管理端口、用户名密码）。

**端口冲突**：宿主机的 53 常被 `systemd-resolved` 或 dnsmasq 占用。处理方式二选一：停掉占用方，或把 AdGuard Home 的 DNS 端口改成 5353 并在路由器做转发（不推荐，会增加故障面）。

### 2.2 路由器侧对接（关键，做错等于没做）

1. 路由器 → LAN/DHCP 设置 → **DHCP 下发的 DNS 服务器** 改为 AdGuard Home 的 IP。
2. **同时改 IPv6 的 DNS（RA/DHCPv6）**。这是最常见的漏配：设备会优先走 IPv6 DNS，绕过拦截，表现为"部分设备有效、部分无效"。
3. 不要改 WAN 侧 DNS——那是路由器自己上网用的，改了不影响下发给设备的值。
4. 保存后，让盒子**断开重连 Wi-Fi 或重启**，才会拿到新 DNS。

### 2.3 抓自家设备的广告域名（本手册最关键的一步）

1. AdGuard Home → 查询日志 → 按客户端 IP 过滤出盒子。
2. 在盒子上**冷启动一次**（断电重插），完整走一遍：开机 → 桌面 → 打开常用 App → 进设置。
3. 回到日志，按"被拦截/未拦截"排序，找**高频、且明显是广告/统计**的域名。
4. 先加入**黑名单**（不要直接加规则文件），逐条验证。

### 2.4 判定某个域名该不该拦（四问）

| 问题 | 判据 |
|---|---|
| 是不是广告/统计？ | 域名含 `ad`/`ads`/`track`/`stat`/`log`/`report`/`beacon`；或请求频率异常高 |
| 拦了会不会影响播放？ | 同域名是否也出现在正常播放路径的请求链里 |
| 是否 CDN 主域？ | 形如 `*.akamai*`、`*.cdn*`、`*.aliyuncs*`、`*.qcloud*` 一律不拦 |
| 是否 OTA / 鉴权？ | 含 `ota`/`upgrade`/`auth`/`token` 的，除非明确要禁更新，否则保留 |

**拦截后必须立刻验证**：起播一个视频、打开应用商店、触发一次搜索。任一项失败，先撤销这条规则再加下一条。

---

## 3. 方案 B：盒子 Private DNS

```bash
# 0) 先验证端点可达，不通会整机断网
adb shell ping -c 2 dns.adguard-dns.com

# 1) 设为指定主机名（严格模式：解析失败即断网，拦截最彻底）
adb shell settings put global private_dns_mode hostname
adb shell settings put global private_dns_specifier dns.adguard-dns.com

# 备选：机会式（不强制，失败自动回落，更安全但不拦截）
adb shell settings put global private_dns_mode opportunistic

# 2) 回滚
adb shell settings put global private_dns_mode off
```

**注意**：`private_dns_specifier` 只填**主机名**，不要带 `https://`、不要带路径。填错的表现是"网络正常但所有 HTTPS 失败"或"设置不生效"。

### 可用端点

| 提供方 | DoT 主机名（填这里） | 特点 |
|---|---|---|
| AdGuard DNS | `dns.adguard-dns.com` | 默认拦截广告与跟踪 |
| AdGuard DNS（家庭） | `family.adguard-dns.com` | 额外拦成人内容 |
| Cloudflare | `one.one.one.one` | 不拦截，仅加速/隐私 |
| Google | `dns.google` | 不拦截 |
| Quad9 | `dns.quad9.net` | 拦恶意域名，不拦广告 |

**要"去广告"就必须选带拦截的端点**（AdGuard 系）。Cloudflare/Google 只换了解析服务器，不会去广告——这是最常见的误解。

### 验证

```bash
adb shell settings get global private_dns_mode
adb shell getprop net.dns1                     # 旧字段，部分 ROM 无值
adb shell dumpsys connectivity | grep -i dns   # 看实际生效配置
adb shell ping -c 1 doubleclick.net            # 应解析失败或被指向黑洞
```

---

## 4. 方案 C：hosts（仅 root，且仅临时用）

```bash
# 备份
adb shell su -c 'cp /system/etc/hosts /data/local/tmp/hosts.bak'

# 写入
adb pull /system/etc/hosts ./hosts.orig
# 编辑后推送
adb push hosts.new /data/local/tmp/hosts
adb shell su -c 'mount -o rw,remount /system'
adb shell su -c 'cp /data/local/tmp/hosts /system/etc/hosts'
adb shell su -c 'chmod 644 /system/etc/hosts'
adb shell su -c 'mount -o ro,remount /system'

# 回滚
adb shell su -c 'mount -o rw,remount /system && cp /data/local/tmp/hosts.bak /system/etc/hosts'
```

hosts 的三个硬伤：**OTA 会覆盖**、**只精确匹配域名**（对 IP 直连与 CDN 无效）、**格式错误会导致整机无网**（必须保证没有 BOM、行尾为 LF、每行 `IP 域名` 用单个空格或制表符分隔）。

---

## 5. 域名分类策略（不要无脑全拦）

| 类别 | 处理 | 理由 |
|---|---|---|
| 广告投放域 | 拦 | 目标 |
| 埋点/统计域 | 拦（可分批） | 减流量与后台，但个别 App 会因上报失败而卡启动 |
| 推送通道 | **不拦** | 拦了部分应用通知全失，甚至起不来 |
| CDN / 视频分发 | **不拦** | 拦了直接不能播 |
| OTA / 升级 | 按需 | 想禁更新就拦，但要接受无安全补丁 |
| 鉴权 / DRM 许可 | **不拦** | 拦了付费内容黑屏 |
| 时间同步（NTP） | **不拦** | 时间错乱会导致 HTTPS 证书校验失败 |

**分批原则**：一轮最多加 10 条规则，加完立刻验证播放、商店、搜索三项。出问题定位在最近 10 条之内。

---

## 6. 效果验证清单

```bash
# DNS 是否指向预期
adb shell dumpsys connectivity | grep -i dns

# 广告域是否被拦（应超时或解析失败）
adb shell ping -c 1 doubleclick.net
adb shell ping -c 1 googleadservices.com

# 正常服务是否可用（必须能通）
adb shell ping -c 1 <你的视频 App 主域名>
adb shell ping -c 1 time.android.com
```

人工验证五项：冷启动无开机广告 / 桌面无贴片 / 应用内无开屏 / 视频能起播 / 商店能打开。

---

## 7. 常见反效果与成因

| 现象 | 成因 | 处置 |
|---|---|---|
| 全屋设备断网 | AdGuard Home 挂了但 DHCP 仍指向它 | 路由器先改回公共 DNS；给 AGH 配 `--restart` 与健康检查 |
| 只有部分设备生效 | IPv6 DNS 未一并下发 | 改 RA/DHCPv6 的 DNS |
| 视频一直转圈 | 拦了 CDN 或 DRM 许可域 | 查日志放开对应域 |
| 应用启动变慢/闪退 | 拦了埋点域导致超时重试 | 放开该域，或改用"仅拦广告域"的规则集 |
| 设置 Private DNS 后无网 | 端点不可达 / 填了 URL | `private_dns_mode off` 回滚，改填纯主机名 |
| 广告几天后又回来 | 厂商通过远程配置下发新域名 | 回到 §2.3，重新抓一轮日志补规则 |
