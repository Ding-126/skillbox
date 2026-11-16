# 包名清单：必守 / 可停用 / 广告候选

**这份清单是"候选集"，不是"执行清单"。** 每一行在用之前必须用 `dumpsys package <pkg>` 在本机确认存在且用途一致。不同 ROM 会复用同名包但功能不同。

---

## 0. 枚举与筛选的正确姿势

```bash
# 全量留档（必做，回滚依据）
adb shell pm list packages -f > before-packages.txt

# 系统包 / 第三方包分开看
adb shell pm list packages -s
adb shell pm list packages -3

# 广告候选：用词边界，避免误命中
adb shell pm list packages | grep -Ei '\.(ad|ads|advert|advertise|advertisement|advertising|promot|promotion|splash|push|recommend)($|\.)'

# 确认包的实质
adb shell dumpsys package <pkg> | grep -E 'versionName|firstInstallTime|lastUpdateTime|pkgFlags|codePath|sharedUser'
adb shell pm path <pkg>
```

**高危误报词**：`ad` 会命中 `downloads`、`adapter`、`shadow`；`push` 会命中推送**通道**（部分系统通知依赖它）；`market` 可能是应用商店本体。**词根只用来缩小范围，判定必须看 `codePath` 与签名。**

判据：
- `codePath` 在 `/data/app/` → 后装应用，可放心停用。
- `codePath` 在 `/system/`、`/system_ext/`、`/product/`、`/vendor/` → 系统预装，必须先停用观察。
- `sharedUser` 与系统关键包共享 uid → **不要动**。

---

## 1. 绝对不动（停用即事故）

AOSP 通用包名，这些在几乎所有 Android TV 设备上都存在且关键：

| 包名 | 作用 | 停用后果 |
|---|---|---|
| `android` | framework 本体 | 无法开机 |
| `com.android.systemui` | 状态栏/导航/音量 UI | 黑屏或界面全失 |
| `com.android.settings` | 系统设置 | 无法进入设置，等于锁死 |
| `com.android.shell` | adb 执行载体 | 断掉 ADB 后无法恢复 |
| `com.android.phone` | 电话/运营商框架 | 运营商盒子鉴权失败、无网 |
| `com.android.bluetooth` | 蓝牙栈 | 蓝牙遥控/音箱全部失效 |
| `com.android.providers.settings` | 设置存储 | 系统设置无法读写 |
| `com.android.providers.media` | 媒体库 | 本地播放器扫不到文件 |
| `com.android.providers.downloads` | 下载服务 | 应用内下载/更新失败 |
| `com.android.providers.telephony` | 通信数据 | 运营商盒子上网异常 |
| `com.android.inputmethod.latin` | 输入法 | 搜索框无法输入（遥控无软键盘） |
| `com.android.webview` / `com.google.android.webview` | WebView | 大量应用内嵌网页白屏 |
| `com.android.packageinstaller` / `com.google.android.packageinstaller` | 安装器 | 无法安装 APK |
| `com.android.keychain` / `com.android.certinstaller` | 证书 | HTTPS/DRM 异常 |
| `com.android.documentsui` | 文件选择器 | U 盘/文件选择失效 |
| 当前唯一的 launcher（`com.android.launcher3` 或厂商桌面） | 桌面 | 黑屏无界面 |
| Widevine / DRM 相关（`pm list packages \| grep -i widevine`） | 版权解密 | 付费内容全黑屏 |

**launcher 例外**：只有在已设好新桌面、且 Home 键验证通过后才可停用原桌面。见 SKILL §4.4。

---

## 2. 值得停用的类型（按收益排序）

不绑定具体包名，只给**类型 + 识别特征 + 典型收益**。你的设备上具体叫什么，用 §0 的枚举确认。

| 类型 | 识别特征 | 收益 | 停用风险 |
|---|---|---|---|
| 广告 SDK / 广告服务 | 包名含 advert/ad/splash；`dumpsys` 无 launcher 组件 | 去贴片、开屏、弹窗 | 低（可能留白块） |
| 运营位/推荐位服务 | 含 recommend/promot/feed；常与桌面同签名 | 去桌面推荐流 | 低 |
| 厂商应用商店 | 含 market/store/appstore；有独立更新通道 | 减后台、减推送 | 中（失去应用更新渠道） |
| 游戏中心 / 电商 / 少儿 | 含 game/shop/mall/kids | 减推送、减内存 | 低 |
| 系统 OTA 更新器 | 含 updater/ota/upgrade | 防回滚（优化成果不被覆盖） | 中（失去安全更新） |
| 语音助手（不用时） | 含 voice/assistant/ai | 减常驻内存与麦克风占用 | 中（语音键失效） |
| 厂商账号/云服务 | 含 account/cloud/sync | 减后台同步 | 中（可能影响推送/找回） |
| 屏保/画报 | 含 screensaver/photowall/wallpaper | 减待机流量与广告 | 低 |
| 运营商定制服务（非 IPTV 播放） | 含 iptv-epg/ott-portal 之外的定制包 | 减后台 | **极高，先做 §3 判断** |

---

## 3. 运营商相关包：先判后动

停用前必须确认**直播是否还能播**。

```bash
# 找出运营商相关包
adb shell pm list packages | grep -Ei 'iptv|ott|epg|auth|multicast|telecom|unicom|cmcc|chinanet|province'

# 关键：找到 IPTV 播放主包并记录，绝不停止
adb shell cmd package resolve-activity --brief -a android.intent.action.VIEW -d "igtv://"
```

规则：
1. 只停用"营销/统计/推送"类定制包，**任何与 `auth`、`epg`、`multicast`、鉴权证书相关的包一律保留**。
2. 停用后立刻测直播，失败就 `pm enable` 恢复。
3. 若设备是唯一收视来源，**一个都别动**，走路由器 DNS 方案。

---

## 4. 执行批次模板

```bash
# 批次 1：确认过的广告 SDK（≤10 个）
adb shell pm disable-user --user 0 pkgA pkgB pkgC
adb reboot
# → 验证：开机 / 联网 / 遥控 / 播视频 / 装应用

# 批次 2：运营位与推荐
adb shell pm disable-user --user 0 pkgD pkgE
adb reboot
# → 验证同上 + 桌面无异常留白

# 批次 3：商店/游戏/少儿（按需）
adb shell pm disable-user --user 0 pkgF pkgG
adb reboot

# 全部稳定 72h 后，转为卸载到用户 0（仍可恢复）
adb shell pm uninstall --user 0 pkgA pkgB pkgC pkgD pkgE pkgF pkgG
```

**卸载前必须能回答**：这个包的恢复命令是什么？（`cmd package install-existing <pkg>`）如果它是系统包且你之后做了分区级改动，恢复链条会断。

---

## 4.5 实测清单：创维 Q0101/Q0108（可作模板，务必逐条复核）

这台设备 `pm disable` 被剥权限，全部改用 `pm block`。**下列包名是实测确认可停用且无功能损失的**，可作为同类创维盒子的起点候选：

```bash
# 广告 / 统计 / 推送
com.skyworthdigital.ott.advert.app      # 广告投放
com.tianci.ad                           # 天赐广告（开机/贴片）
com.skyworthdigital.ottstatsv2          # 统计上报
com.skyworthdigital.logcollector        # 日志上报
com.skyworthdigital.noticewidget        # 公告推送
com.skyworthdigital.ott.guide           # 开机引导（过引导期后无用）

# 更新与商店
com.skyworthdigital.upgrade             # OTA（会推回被卸载的广告包）
com.skyworthdigital.skyappupdate        # 应用更新器
com.mipt.store                          # 商店 + 广告推送（先 uninstall 卸更新层，再 block）

# 无用功能
com.skyworthdigital.autotest            # 工厂测试
com.skyworthdigital.usbbt               # 蓝牙测试
com.skyworthdigital.skyappupdate        # 重复，见上
com.skyworthdigital.SkyPPPoE            # 宽带拨号（走 WiFi 时无用）
com.skyworthdigital.skywechatclient     # 微信遥控
com.skyworthdigital.shortcutkeyssetting # 一键直达（实测停用后按键全正常，省 8.5MB）
com.xiaopaitech.supportsdk              # 小湃投屏 SDK（不用华为 Cast+ 时可停）
```

**实测不可停**（停一个坏一个）：

```bash
com.skyworthdigital.settings       # 设置
com.skyworthdigital.skypowermanager # 电源（禁了关不了机）
com.skyworthdigital.providers      # 数据提供者
com.skyworthdigital.skymediacenter # 媒体中心（本地播放）
com.skyworthdigital.mediarender    # 投屏接收端（PaiCast 就是它，桌面图标同名）
com.skyworthdigital.skycommonpropertymanager  # 白名单守护，动了会被回滚
```

**进程级不可动**（不是包，用 `ps` 看）：`system_server`、`zygote`、`mediaserver`、`surfaceflinger`、`netd`、`vold`、`installd`、`keystore`、`servicemanager`、`adbd`、`dhcpcd`、`gpioservice`（遥控器信号）、`defcontainer`（装 APK）。

---

## 5. 恢复命令

```bash
# 停用 → 恢复
adb shell pm enable <pkg>

# block → 恢复（API≤19 的主力手段）
adb shell pm unblock <pkg>

# 卸载到用户 0 → 恢复（API21+；API<21 无 cmd，只能重装备份 APK）
adb shell cmd package install-existing <pkg>
adb shell cmd package install-existing --user 0 <pkg>

# 批量核对：与留档对比，找出漏掉的
adb shell pm list packages > after-packages.txt
diff <(sort before-packages.txt | sed 's/.*=//') <(sort after-packages.txt)
```

最后一条 `diff` 是唯一可靠的"我到底改了什么"验证手段。每次批量操作后都跑一次，把差异记进执行记录。
