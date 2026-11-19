# OTA 方案（可选）

> 前提：已完成 `README.md` 里的 fork 搭建，CI 能正常出包。
> 本文是**第二期**内容，建议等基础流水线稳跑一两个版本后再启用。

---

## 一、先理解 OTA 为什么默认不能用

Decaid 的 OTA 逻辑（`update_check_service.dart` + `android_updater.dart`）：

```
启动 / 每 12 小时
     ↓
GET api.github.com/repos/{owner}/{repo}/releases
     ↓
跳过 prerelease → 取 assets 里第一个 .apk
     ↓
_isNewerVersion(远端版本, 本地版本)?
     ↓
下载 → 系统安装器 → Android 校验签名
```

对照你的 fork，有两个障碍：

| # | 障碍 | 后果 |
|---|---|---|
| 1 | 数据源写死 `tadelv/reaprime`（= 官方仓库） | 下载官方 APK，签名 `f4ae824f` ≠ 你的 `953a1ad5` → **安装失败** |
| 2 | 同版本重构建时版本号不变 | App 只比 semver，版本相等 → **判定"已是最新"，收不到更新** |

两个都必须解决，否则 OTA 要么装不上，要么收不到更新。

> 注：第 2 点通过 Release 名称里的 `(build N)` 解决，详见第三节 7a–7e。
> 与 tag 前缀（下面第五节）无关——tag 只影响 GitHub 侧的发布机制。

---

## 二、解决方案总览

| 补丁 | 文件 | 解决 |
|---|---|---|
| 4 | `update_check_service.dart` | 障碍 1：数据源 |
| 5 | `app.dart` | 障碍 1：数据源 |
| 6 | `settings_view.dart` | 障碍 1：数据源 |
| **7a-7e** | `android_updater.dart` | **障碍 2：同版本识别** |

全部由 `patch-android11.sh --with-ota` 自动应用（11 处）。

### 补丁 7 的思路

`_isNewerVersion` 只拿到两个版本字符串，拿不到 release 的其它信息。
所以给它「加一条数据通路」：

```
release name: "android11-v0.9.2 (build 42)"
        ↓ 补丁7b 正则解析 build (\d+)
UpdateInfo.buildNumber = 42          ← 补丁7a 新增字段
        ↓ 补丁7d 存入 _pendingBuildNumber
_isNewerVersion:
    版本不同 → 按 semver 比
    版本相同 → 比 build number      ← 补丁7c
        ↓
本地 BuildInfo.buildNumber（编译时 --dart-define 注入）
```

**改动量**：`android_updater.dart` 一个文件，约 30 行，新增 1 个字段 + 1 个私有变量。
`UpdateInfo` 的构造点只有 2 处，且 `buildNumber` 有默认值 `0`，不会破坏 `debugForceUpdate`。

---

## 三、启用步骤

### 3.1 切换补丁脚本

统一脚本用参数切换，不需要换文件：

```bash
cd decaid-android11
git checkout android11

# 预期：11 处全部可应用
DRY_RUN=1 ./patch-android11.sh --with-ota .
```

期望输出：

```
[✓] 补丁模式: OTA 版
[✓] OTA 数据源: UncleIce/decaid-android11
[✓] 补丁1 跳过WebView自检：可应用（DRY RUN 未写入）
...
[✓] 补丁7e 补BuildInfo导入：可应用（DRY RUN 未写入）
[✓] DRY RUN 通过：11 处补丁均可应用（模式：OTA 版）
```

> 如果之前已经跑过基础版，直接加 `--with-ota` 再跑一次即可：
> 脚本会跳过已应用的 3 处，只补上 OTA 的 8 处。

### 3.2 应用并编译

```bash
./patch-android11.sh --with-ota .

# 关键：必须注入 BUILD_NUMBER，否则 OTA 无法识别同版本更新
export VERSION=0.9.2
export BUILD_NUMBER=$(date +%s)     # 或用 CI 的 run_number

flutter build apk --release --target-platform android-arm64 \
  --dart-define=VERSION="$VERSION" \
  --dart-define=BUILD_NUMBER="$BUILD_NUMBER"

# 静态检查
flutter analyze --no-pub
```

### 3.3 替换 workflow

把 `android11-release.yml` 换成 `android11-release-ota.yml`。

**核心差异**：Release 的 `name` 必须包含 `build N`，否则补丁 7b 解析不到：

```yaml
- name: 生成 Release
  uses: softprops/action-gh-release@v2
  with:
    name: "${{ github.ref_name }} (build ${{ github.run_number }})"   # ★ 关键
```

### 3.4 首次升级需手动装

当前平板上跑的是旧包，`BuildInfo.buildNumber` 是 `0`（编译时没注入）。

```
本地版本 0.9.2+0
远端 release v0.9.2 (build 42)
        ↓
版本相同 → 比 build：42 > 0 → 判定有更新 ✅
```

**实际上首次就能 OTA 接上**，不用手动装。前提是旧包的版本号不是 `1.0.0`
（你早期手动编的那个是 `1.0.0+1`，那种情况会判定为降级，需要手动装一次）。

### 3.5 打开自动检查

装上新包后：

```
Settings → UPDATES → Automatic update checks  → 打开
```

之前你把它关了（因为指向官方仓库会装失败）。现在指向自己的 fork，可以开了。

---

## 四、验证方法

### 4.1 不发布就能测（推荐先做）

Debug 构建里有个强制提示的方法：

```dart
// update_check_service.dart:307
void debugForceUpdate({String version = '99.0.0', String? downloadUrl})
```

可以从设置页的开发者选项调用，验证界面能弹出更新提示。

### 4.2 真实链路验证

```bash
# 1. 看 App 查到的是什么
adb logcat -c
adb shell am force-stop net.tadel.reaprime
adb shell am start -n net.tadel.reaprime/com.trim.app.MainActivity 2>/dev/null
sleep 15
adb logcat -d | grep -E "AndroidUpdater|UpdateCheck|Update available"

# 期望看到
# Checking for updates on stable channel (current: 0.9.2+0)
# Update available: 0.9.2
# Same version 0.9.2 but newer build: remote=42 local=0
```

```bash
# 2. 点更新后看下载与安装
adb logcat -d | grep -E "Downloading update|Downloaded update|Installing"
```

### 4.3 关键日志对照表

| 日志 | 含义 |
|---|---|
| `Update available: 0.9.2` | 查到更新 ✅ |
| `Same version 0.9.2 but newer build: remote=42 local=0` | 补丁 7c 生效 ✅ |
| `Already on latest version` | 判定无更新（build 没传对） |
| `No APK found in release` | release 里没有 .apk 资产 |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 签名不一致（Secrets 配错了） |

---

## 五、注意事项

### 5.1 `run_number` 会跨 workflow 共享

`${{ github.run_number }}` 在整个仓库内递增，不是单 workflow 的。
所以 build number 单调递增，符合预期。但**不要用 `run_attempt`**（重跑会重复）。

### 5.2 GitHub API 限流 60 次/小时

OTA 每次检查消耗 1 次。同一出口 IP 共享额度。

- 已在 App 设置里支持配 GitHub Token（提额到 5000/小时）
- 平时一天 2 次检查，完全够用

### 5.3 官方版和新版不能互装

| 从 | 到 | 结果 |
|---|---|---|
| 官方版 | 你的版 | 必须卸载（签名不同） |
| 你的旧版 | 你的新版 | ✅ 直接覆盖，数据保留 |

### 5.4 上游改了 `android_updater.dart` 会冲突

补丁 7 改动较深（加字段、改方法、加 import）。
上游若重构这个文件，`patch-android11.sh --with-ota` 会明确报错并给出排查命令。这时：

```bash
git fetch upstream --tags
git checkout -b fix upstream/v0.9.4
DRY_RUN=1 ./patch-android11.sh --with-ota .   # 看哪一条失败
# 按新代码调整对应 old/new 字符串
```

### 5.5 是否值得做？

| 收益 | 成本 |
|---|---|
| 用户不用手动下载装包 | 多 5 个补丁，跟进上游时多一个冲突点 |
| 修 bug 能快速触达 | 需要维护 build number 递增 |

如果你只是自己一台平板用，**手动 `adb install -r` 更省心**。
OTA 的价值在「多设备 / 给他人用」。

---

## 六、回退

OTA 出问题时快速退回基础版：

```bash
git checkout android11
git reset --hard android11-base     # 回到打 OTA 补丁前

./patch-android11.sh .              # 不带 --with-ota
git commit -am "revert: 回到基础版（不含 OTA）"
```

已安装的 OTA 版本可以照常收到新包，只是不再有「同版本更新」识别能力
（发新版本号时仍能正常提示）。
