# 低版本 / 低配设备降级路径（API ≤ 19、RAM < 1GB）

**这份文档存在的理由**：标准 Android 优化手段在定制固件上可能整体失效。厂商会删权限、锁桌面、加白名单、服务器下发配置。SKILL.md 的常规路径走不通时，来这一份找备选。

实证来源：创维 Q0101（自报 **Q0108** / `dolphin_fvd_p2`，全志 H2 双核 A7 1.0GHz，**507MB RAM**，Android **4.4.2 / API 19**，1280×720@160dpi，无 root，`dev-keys` 但 platform key 为厂商自签）。下文标「实测」的均为该机验证结果，其他机型需复核。

---

## 1. 先做能力探测，别假设 API 存在

这台机器上 `pm disable-user` 存在但无权限、`cmd package` 完全不存在、`set-home-activity` 不存在。**不探测就写脚本，等于盲写。**

### 1.1 四组探测（5 分钟跑完）

```bash
A=adb; IP=192.168.1.x

# ① pm 支持哪些子命令
$A shell pm 2>&1 | head -40

# ② shell 被授予了哪些权限（关键：assign-permission uid="shell" 是否被删）
$A shell cat /system/etc/permissions/platform.xml | grep -A40 'uid="shell"'

# ③ 关键命令是否存在
$A shell which cmd; $A shell which su; $A shell which setprop
$A shell 'cmd package 2>&1 | head -3'    # 报错 = 不存在（API<21 常态）

# ④ settings 哪些命名空间可写
$A shell settings list system | head -5
$A shell settings list secure | head -5
$A shell settings list global | head -5
```

### 1.2 探测结果 → 能力矩阵

| 探测项 | 结果 | 可走路径 |
|---|---|---|
| `pm disable-user` 可执行 | 返回 RC=0 | 标准路径（SKILL §4.1） |
| `pm disable-user` 报 SecurityException | 权限被剥 | **降级到 `pm block`（§2）** |
| `cmd package` 不存在 | API<21 或固件精简 | 不能用 `set-home-activity` / `install-existing`，走 §3 |
| `su` 存在且可执行 | uid=0 | 可进 SKILL §4.7 |
| `su` 不存在 / `adb root` 假成功 | 见 §1.3 | 锁死在应用层 |
| `persist.adb.tcp.port` 写不进 | 常态 | ADB 重启即失联，见 §5 |

### 1.3 `adb root` 假成功的识别

```bash
adb root                      # 提示 restarting adbd as root
adb shell id                  # 仍是 uid=2000(shell) → 假成功
adb shell getprop service.adb.root
adb shell ps | grep adbd
```

实测本机：`setprop service.adb.root 1` + `kill -9 adbd` 后 adbd 重启，**仍以 shell 运行**，说明固件的 adbd 被裁过。此时不要继续尝试提权，直接走 `pm block`。

判定 `platform.xml` 权限被删：

```bash
adb shell cat /system/etc/permissions/platform.xml | grep -c 'uid="shell"'
# 0 = 整块 assign-permission 被删（实测本机为 0）
```

后果：`CHANGE_COMPONENT_ENABLED_STATE`、`INSTALL_PACKAGES`、`DELETE_PACKAGES` 全部缺失。表现是 `pm disable` 报错、`pm install` 被拒，但 `pm block` 与 `am start` 仍可用——因为这两个走的不是同一套权限检查。

---

## 2. `pm block` / `pm unblock`（权限被剥时的主力）

### 2.1 行为

```bash
adb shell pm block <pkg>      # Package ... new blocked state: true
adb shell pm unblock <pkg>    # 恢复
```

- **比 disable 更彻底**：包从系统查询中消失、进程被 force-stop、不能再被隐式拉起。
- **状态写入 `packages.xml`**，重启保持（实测重启 3 次仍 blocked）。
- 与 `disable` 的关键差别：`disable` 走 `CHANGE_COMPONENT_ENABLED_STATE` 权限（可能被删）；`block` 走应用封禁接口，**本机实测有权限**。
- **版本边界**：4.x 实测可用。较新 Android（8+）`pm block` 行为有变或移除，新版设备仍应首选 `disable-user`，用 `block` 前先测。

### 2.2 回滚

```bash
adb shell pm unblock <pkg>
```

API<21 **没有** `cmd package install-existing`，所以：

- 只 `block` 过的包 → `unblock` 即可，简单。
- 如果先 `uninstall` 了（系统应用只卸更新层）→ 原 `/system/app` 版本仍在，`block` 后即可，不需要重装。
- 如果是第三方应用被 `pm uninstall` → 必须保留 APK 备份，重新 `adb install`。**动手前必须备份**：

```bash
# 备份所有第三方 APK（体积可控时）
adb shell pm list packages -3 | sed 's/package://' | while read p; do
  path=$(adb shell pm path $p | sed 's/package://' | tr -d '\r')
  adb pull "$path" "./apk-backup/${p}.apk"
done
```

### 2.3 实测效果（本机）

| 包 | 操作 | 结果 |
|---|---|---|
| `com.skyworthdigital.sky2dlauncherv4`（原桌面） | `pm block` | 系统 HOME 唯一候选变成自建桌面，`from pid 0` 直接拉起 |
| `com.mipt.store`（应用商店 + 广告推送） | 先 `pm uninstall` 回退到 `/system/app`，再 `pm block` | 重启后完全不启动，空闲内存 101MB → 252MB |
| `com.skyworthdigital.ott.advert.app` | `pm block` | 进程消失 |
| `com.tianci.ad` | `pm block` | 进程消失 |
| `com.skyworthdigital.shortcutkeyssetting`（一键直达） | `pm block` | 省 8.5MB；实测中键上下左右/确认/返回/主页全部正常 |
| `com.skyworthdigital.upgrade`（OTA） | `pm block` | 防止广告包被 OTA 推回（**曾发生**） |

**OTA 会推回被卸载的广告包**——实测卸载 `advert.app` 后被系统重新装回。所以"卸载"在定制固件上不等于"解决"，必须 `block` 掉 `upgrade` 类包，或接受反复。

### 2.4 一个包两个进程 ≠ 两个包

实测 `com.mipt.store` 有两个进程（主进程 + `popadvert.OptionPushService`），用户误判为"两个包"。**诊断按包名，不按进程数**：

```bash
adb shell dumpsys package com.mipt.store | grep -E 'versionName|codePath'
adb shell ps | awk '/mipt/{printf "%s RSS=%sKB\n",$9,$5}'
```

---

## 3. 桌面接管的三种路径（按可用性排序）

### 3.1 决策树

```
新桌面已装且能手动启动？
├─ 否 → 先装/先修，不要动原桌面（否则黑屏）
└─ 是
   ├─ ① cmd package set-home-activity 可用（API21+）
   │     → cmd package set-home-activity <pkg>/<activity>
   ├─ ② 不可用，但系统选择器正常（RAM ≥ 1GB）
   │     → 按 Home 键，在弹窗里选新桌面 + 勾"始终"
   └─ ③ 不可用，且选择器会崩（低内存设备常见）
         → pm block 原桌面，让系统唯一候选直接拉起
```

### 3.2 路径 ③ 的机制与风险

实测：`ResolverActivity` 在 507MB 内存的机器上**必崩**——一旦触发桌面选择器就黑屏/闪回。所以不能指望"按 Home 键选始终"。

`pm block` 原桌面后，HOME 的候选只剩一个，系统不做选择，直接启动：

```
START u0 {act=MAIN cat=[HOME] cmp=com.android.provision.tvhome/.HomeActivity} from pid 0
```

`from pid 0` = 系统在启动过程中自行拉起，不经过选择器。

**执行前必须做的验证**（顺序不能反）：

```bash
# 1) 新桌面能手动起来且不崩
adb shell am start -n <newpkg>/<activity>; sleep 3
adb shell dumpsys activity | grep mResumedActivity
adb shell logcat -d | grep -c "FATAL EXCEPTION"     # 必须为 0

# 2) 新桌面声明了 HOME 且优先级够高
adb shell dumpsys package <newpkg> | grep -A6 "category.HOME"

# 3) 才 block 原桌面
adb shell pm block <oldlauncher.pkg>
adb shell input keyevent 3; sleep 2
adb shell dumpsys activity | grep mResumedActivity   # 必须停在新桌面

# 4) 连按 Home 3 次不进选择器、不崩
```

### 3.3 新装应用处于 stopped 状态

新装的包不会被 `BOOT_COMPLETED` 唤醒——**必须先 `am start` 一次解除 stopped**。这是"开机自启没生效"的最常见原因，与代码无关。

```bash
adb shell am start -n <pkg>/<activity>     # 解除 stopped
adb shell dumpsys package <pkg> | grep -i stopped
```

---

## 4. 厂商白名单与守护进程回滚

### 4.1 现象

改动生效 → 重启或数小时后被还原 → 日志出现拦截记录。

### 4.2 本机实测机制（创维）

反编译 `services.jar` 得到：

```java
// SkyworthConfig.isInCurrWhiteList(key, pkg, list)
if (pkg.startsWith("com.skyworthdigital"))  → 必须与名单项完全相等
else                                        → 名单中任一项是 pkg 的前缀即通过

// 默认名单（签名校验失败时也退回用它）
HOME_WHITELIST_DEFAULT  : "com.skyworthdigital.sky2dlauncher / com.android.provision / com.ktcp.launcher / com.xiaopaitech.plauncher"
START_WHITELIST_DEFAULT : "com.snm.upgrade / com.tianci.ad / com.android / android / system ..."
```

白名单存放位置（settings system 命名空间）：

```bash
adb shell settings get system com.skyworthdigital.homewhitelist
adb shell settings get system com.skyworthdigital.startupwhitelist
```

**两个致命事实**：

1. **服务器下发覆盖**：`getAppWhiteList` 接口，开机 1 分钟后 + 每 2 小时刷新一次。手动 `settings put` 写入的值**每次都会被覆盖**（实测）。
2. **分隔符以实测为准**：读出来是 `/` 分隔就用 `/` 追加，别凭空用逗号。

### 4.3 可复用的绕过思路

既然白名单对非本厂包采用**前缀匹配**，而默认名单里含 `com.android` / `com.android.provision`，那么**把自己的包名改成 `com.android.provision.<任意>` 即可天然通过校验**——不需要伪造签名，也不会被守护进程回滚。

实测：包名改为 `com.android.provision.tvhome` 后，HOME 与开机广播双双放行，三次重启稳定。

**这条思路的通用性**：任何"按前缀匹配白名单"的厂商实现都存在这个缺口。识别方法：

```bash
# 反编译 services.jar，找白名单判定函数
adb pull /system/framework/services.jar
unzip -oq services.jar -d svc
dexdump -d svc/classes.dex > dump.txt
grep -n -iE 'whitelist|isInNameList|isInCurrWhiteList' dump.txt | head
```

看到 `startsWith` + 名单遍历，基本就是这个模式。

### 4.4 不要走的路（已证伪）

| 路线 | 结果 | 证据 |
|---|---|---|
| 用 AOSP testkey 签 `android.uid.system` | `INSTALL_FAILED_SHARED_USER_INCOMPATIBLE` | framework-res.apk 由厂商自签（证书主体含厂商名与邮箱），私钥不在设备上 |
| `dev-keys` 标签当成有 root | 只是构建标签 | `ro.build.tags` 含 dev-keys 但 platform key 仍是厂商的 |
| `adb root` / `setprop service.adb.root 1` | adbd 重启后仍是 shell | 实测 |
| 全盘找 `*.pk8` 私钥 | 不存在 | 查过 `/system/etc/security`、`/vendor` |

**结论：定制固件上的 system uid 路线先证伪再放弃，不要浪费两小时。**

---

## 5. ADB 持久性（动手前必须确认）

```bash
adb shell getprop service.adb.tcp.port      # 临时属性，重启丢失
adb shell getprop persist.adb.tcp.port      # 空 = 未持久化
adb shell setprop persist.adb.tcp.port 5555 # 实测被拒（shell 无权限）
```

**风险链**：改了桌面/系统包 → 重启 → ADB 没回来 → 桌面起不来 → 无法远程救 → 只能恢复出厂或线刷。

**规则**：

1. 动手前先测一次"重启后 ADB 是否自动回来"。测法：重启 → 等待 → `adb connect`。不回来就认定 ADB 是临时的。
2. ADB 临时可用时，**所有改动必须满足"无 ADB 也能自愈"**：新桌面能独立启动、不改系统分区、`pm block` 可逆（但要能通过遥控器进入设置恢复）。
3. 完成关键改动后先不重启，用 `am force-stop` + `am start` 模拟，确认前台正确再重启验证。
4. 万一失联：恢复出厂（遥控器进设置）、U 盘升级包、或线刷官方固件。

---

## 6. 低配设备的性能真相（别做伪优化）

### 6.1 定时杀后台是错的（有实测数据）

| 场景 | 启动耗时 |
|---|---|
| B 站冷启动 | **5.4 s** |
| B 站热启动（进程在） | **2.0 s** |
| 差 | **3.4 s** |

定时清理后台 → 每次回桌面后应用被回收 → 下次进入多等 3.4 秒。**这是"感觉更卡了"的直接原因**，且是优化本身造成的回归。

正确做法：只在**明确闲置**（回桌面超时）且**内存真的紧张**时清理，并给常用应用加白名单。但即便是条件触发，也要用对指标（见 §6.2）。

### 6.2 `MemFree` 是错误指标

`MemFree` 不含 page cache。应用被回收后内存变成缓存页，`MemFree` 上升但系统并不"更健康"；反之缓存被占用时 `MemFree` 很低但系统完全正常。

```bash
grep -E 'MemTotal|MemFree|MemAvailable|Cached' /proc/meminfo   # 设备上 cat
adb shell cat /proc/meminfo | grep -iE 'MemTotal|MemFree|MemAvailable'
```

- 内核 ≥ 3.14 有 `MemAvailable`，用它。
- 老内核无 `MemAvailable` 时，用 `MemFree + Cached` 近似，或 `dumpsys meminfo` 的 PSS 总和。
- 实测本机 `MemFree` 阈值 100MB 几乎每次回桌面都触发，把 B 站杀掉了。阈值降到 60MB 才合理——但根本结论是**不该加这层逻辑**。

### 6.3 可动的与不可动的

**可动**（实测省内存，无功能损失）：

| 项 | 省 | 说明 |
|---|---|---|
| 禁用 15 个后台服务包 | 累计 60MB+ | 日志上报、工厂测试、开机引导、公告推送、PPPoE、微信遥控等 |
| 动画三件套置 0 | 0 | 观感提升，免费 |
| 长按判定 500ms → 350ms | 0 | 遥控手感 |
| 换极简桌面 | 56MB | 桌面 82MB → 26MB |

**不可动**（停一个坏一个）：

| 类别 | 例子 | 后果 |
|---|---|---|
| Android 骨架 | `system_server` `zygote` `mediaserver` `systemui` `surfaceflinger` `netd` `vold` `installd` `keystore` `servicemanager` `adbd` | 崩溃/黑屏 |
| 厂商 HAL | `gpioservice`（遥控器信号）`securefileserver` `isomountmanagerservice` `systemmixservice` `skylogd` | 丢遥控器/HDMI 输出 |
| 守护进程 | `skycommonpropertymanager`（白名单管理者）`defcontainer`（装 APK）`keychain` | 白名单被回滚/装不了应用/证书异常 |
| 用户在用的 | 输入法、投屏接收端、桌面 | 功能缺失 |

**第 15 个包之后就没有净收益了**：再往下每个 MB 都要用一个具体能力去换。

### 6.4 硬件瓶颈要说清

实测空闲温度 59°C，全志方案过热会降频，表现为"看久了越点越慢"。**挪出电视背后的密闭空间比任何软件优化都有效。**

---

## 7. 设备发现失败的另一类原因：组播（不是端口问题）

SKILL §1.2 的 nmap 扫描只解决"我能不能找到设备"。反向场景——**手机搜不到盒子上的投屏/渲染服务**——是另一套问题。

### 7.1 三个真实成因（实测）

| 成因 | 表现 | 修法 |
|---|---|---|
| SSDP 组播绑错网卡 | 单播能应答，手机广播搜索时无响应 | 显式绑定 `wlan0`：`joinGroup(239.255.255.250, wlan0)` |
| 服务启动时 WiFi 未就绪 | 开机后永久失效，`ip=null` | 监听 IP 变化（由无到有、IP 变更）→ 重建组播绑定 |
| 后台被厂商杀 | 独立 App 存活约 3 分钟 | 并入常驻应用（如桌面）；或进白名单 |

### 7.2 乐播类 SDK 的二次过滤

实测：DLNA 应答正常、设备可见，但某些 App 的设备列表里不显示。原因是这些 App 集成乐播 SDK，拿到设备后按厂商白名单二次过滤，且 `manufacturer`/`modelName` 为 `local` / `Windows Media Player` 会被判定为"电脑"丢弃。

改为设备出厂标识（如 `Skyworth` / `Skyworth TV`）后可显示。

**但**：抖音、快手这类用乐播私有协议（Lelink）直接握手，不发 DLNA 广播搜索——日志里 `M-SEARCH` 记录为零即可确认。这种情况改什么都不行，直接放弃。

判别命令（在接收端抓）：

```bash
adb logcat -s TVCast | grep -i "M-SEARCH"     # 有记录 = 发了 DLNA；零记录 = 纯私有协议
```

---

## 8. APK 兼容性预检（装之前先验，别装完再崩）

```bash
aapt dump badging app.apk | grep -E "^package:|sdkVersion|targetSdkVersion|native-code"
# 或
aapt2 dump badging app.apk | head -5
```

### 8.1 四个必查项

| 项 | 判定 | 失败后果 |
|---|---|---|
| `sdkVersion`（minSdk） | 必须 ≤ 设备 SDK | `INSTALL_FAILED_OLDER_SDK` |
| `native-code` | 必须含设备 ABI（老盒子多为 `armeabi-v7a`） | 装上即崩 |
| 包体积 | 低配机上 > 100MB 基本不可用 | 内存不足、LOOPER 卡死 |
| MD5 | 与来源记录一致 | 来源被改过，不接受 |

### 8.2 minSdk 会撒谎

实测：某影视 App TV 版标称"适用于 Android 6 以下"，minSdk 18，装上去启动即崩：

```
java.lang.NoClassDefFoundError: android.system.Os
  at ...ProxyApplication.attachBaseContext
```

`android.system.Os` 是 **API 21** 才有的类——加固壳用了高版本接口，`minSdk` 标称是假的。

**判定方法**：minSdk 达标不等于能跑。对加固/混淆包，看启动日志是否 `NoClassDefFoundError` 指向 `android.system.*`、`java.util.function.*`、`java.time.*` 等新 API 包名。

### 8.3 权限红旗

播放器类 App 申请下列权限，直接不装：

```
RECORD_AUDIO                  录音
READ_PHONE_STATE              设备/通话信息
REQUEST_INSTALL_PACKAGES      静默安装其他 App
MOUNT_UNMOUNT_FILESYSTEMS     挂载文件系统
USE_BIOMETRIC / USE_FINGERPRINT
GET_TASKS                     读取正在运行的应用
```

---

## 9. 广告处理的三级优先（成本递增）

实测顺序，**先做便宜的**：

### 9.1 第一级：手动跳过（成本 0）

投屏/开屏广告页面常自带"按 OK 键跳过"提示。实测：按一次遥控器 OK 键，广告立即消失，且**后续多次投屏不再出现**（广告接口返回 0 条素材）。

```
AD_ADRequest:requestAD adPosId:2
GET http://adengt.hpplay.cn/adEngine/fetchCreative → 200
AD_ADRequest:getValidADs adBean size 0    ← 按过 OK 后返回空
```

**检查动作**：看到广告先按 OK，别急着改系统。

### 9.2 第二级：精确域名拦截（成本低，风险可控）

**只拦广告引擎，不碰业务域。** 实测某投屏 App 的域名分层：

| 域名 | 作用 | 处理 |
|---|---|---|
| `adeng.hpplay.cn` / `adengt.hpplay.cn` | 广告投放 `fetchCreative` | 可拦 |
| `adeng.lebo.com.cn` | 备用广告引擎（拦了 `.cn` 会切到它） | 必须一起拦 |
| `ad.hpplay.cn` / `adcdn.hpplay.cn` | 广告资源 | 可拦 |
| `rp.hpplay.cn` / `rps.hpplay.cn` / `sl.hpplay.cn` | 曝光/统计上报 | 可拦，无感 |
| `hotupgrade.hpplay.cn` / `tvapp.hpplay.cn` | 升级推送 | 可拦 |
| `sdkauth.hpplay.cn` / `vipauth.hpplay.cn` | **会员鉴权** | 拦了大概率废掉功能 |
| `imdns.hpplay.cn` | 设备发现 | **绝对不拦** |
| `pin.hpplay.cn` / `gslb.hpplay.cn` | 配对/调度 | **绝对不拦** |
| `hpplay.cdn.cibn.cc` | 视频 CDN | **绝对不拦** |
| `h5.hpplay.com.cn` | 活动/会员 H5 | 可拦，但可能影响活动页 |

**关键教训：广告域名通常有备用域（`.cn` / `.com.cn` 双份）。只拦一个等于没拦。**

**方法优先于清单**：以上域名来自抓包实测，换版本就会变。正确做法是抓自己设备的请求（`adb logcat | grep -iE 'http|ad'`，或 DNS 查询日志），按上表分类后分批加、每批验证。

### 9.3 第三级：改系统（成本高，多数情况不值得）

- 无 root：`/system` 只读，hosts 与 iptables 都用不了。
- `pm block` 只能整包停用——**广告代码在宿主 App 的主包里时，停用 = 功能一起废**。
- 自己写一个无广告替代端（实测可行：32KB 纯 DLNA 接收端，常驻 7MB，对比原 App 50MB），但工程量与维护成本要自担。

**判断标准**：广告能一键跳过 → 不做 9.2；9.2 能覆盖 → 不做 9.3；9.3 只在"广告无法跳过 + 域名拦截无效 + 有替代实现"三条同时成立时才考虑。

### 9.4 会员墙 ≠ 广告墙

实测某投屏 App 8.x 把投屏改成免费额度制：`VideoRightsManager:requestCastCost` 每次投屏前向服务器查价，`VipAuthWebView` 每 10 秒轮询等待扫码。

**这类限制无法通过屏蔽广告域名解决**，也不建议降级或破解（来源不可信 + 绕过付费墙）。可行路径只有：换走标准 DLNA 的客户端、或走硬件（转接线）。

---

## 10. 本案例的可复用结论（沉淀成规则）

1. **先探测能力，再选方案**。文档里的命令在定制固件上可能不存在或无权限。
2. **`pm block` 是 `pm disable` 失效后的第一备选**，比卸载更安全（写 `packages.xml`、重启保持、`unblock` 可还原）。
3. **改系统前先确认 ADB 是否持久**。不持久就要保证"无 ADB 也能自愈"。
4. **厂商白名单按前缀匹配时，改包名就是通行证**——先反编译确认规则，再改。
5. **凡是被回滚的改动，先找服务器下发通道**，改本地值没用。
6. **杀后台不是优化**。冷启动代价 3.4 秒，远超省下的内存价值。
7. **`MemFree` 不能当内存健康指标**。
8. **先按 OK 跳过，再考虑改系统**。
9. **广告域名有备用域，且与业务域同源**——精确打击，绝不全域封杀。
10. **低配设备的终点是硬件**：507MB RAM + 双核 A7 上，软件优化到 15 个包禁用、动画归零、桌面换掉之后，再往下每 1MB 都要牺牲一个功能。
