# Decaid for Android 11

> 让 [Decaid](https://github.com/decentespresso/decaid) 在 Android 11 及更早的设备上
> 直接内嵌显示咖啡机界面，而不是只给你一个"用浏览器打开"的卡片。

**本仓库**：https://github.com/UncleIce/decaid-android11
**上游项目**：https://github.com/decentespresso/decaid —— 功能、文档、使用说明请先看那里

> ⚠️ **非官方构建**。本项目是个人 fork，与 Decent Espresso 无关。
> 所有功能归功于上游作者，本仓库只做了一处针对旧版 Android 的适配。

---

## 这个 fork 解决什么问题

Decaid 的 `lib/src/app.dart` 里有这么一段：

```dart
Future<void> _resolveDegradedAndroid() async {
  final info = await DeviceInfoPlugin().androidInfo;
  if (mounted && info.version.sdkInt < 31) {      // ← Android 12 以下
    setState(() => _degradedAndroid = true);      //    标记为"降级模式"
  }
}
```

被标记降级后，`_navigateAfterOnboarding()` 会直接返回，不打开皮肤：

```dart
if (!supportedPlatforms || _degradedAndroid) return;
```

结果：**Android 11 及以前的设备打开 App 后，只看到一个引导卡片，
让你去系统浏览器访问本地 Web 界面**，无法在 App 内使用。

而实际上：

| 项目 | 值 |
|---|---|
| 上游 `minSdk` | **28**（Android 9） |
| 兼容性检查的真实门槛 | `sdkInt < 29` 才判定不兼容 |
| 降级判定门槛 | `sdkInt < 31`（Android 12） |

两者不一致 —— 系统允许安装，兼容检查也认为 Android 11 没问题，
但界面逻辑仍然按 Android 12+ 处理。这个 fork 去掉的就是这处限制。

---

## 支持范围

### 已支持

| 能力 | 说明 |
|---|---|
| Android 11（SDK 30）内嵌显示 | 核心改动 |
| Android 12+ | 与官方版本行为一致 |
| Android 9–10（SDK 28–29） | 本补丁同样放行，但**未在实机验证**；这些版本 WebView 内核较旧，皮肤可能有渲染问题 |
| 所有上游功能 | 咖啡机连接、萃取、秤、皮肤、插件等，与官方版本相同 |
| 跟随上游更新 | 自动检测上游新版本，补丁可应用时自动构建发布 |

### 实测环境

| 项目 | 值 |
|---|---|
| 设备 | Samsung Galaxy Tab S5e（SM-T727U） |
| 系统 | Android 11，SDK 30 |
| 屏幕 | 1600×2560，density 360 |
| 基于版本 | upstream `v0.9.2` |

### 不支持

| 项目 | 原因 |
|---|---|
| iOS / macOS / Windows / Linux | 本 fork 只构建 Android arm64 |
| Android 8 及更早 | 上游 `minSdk = 28`，装不上 |
| 官方 OTA 更新 | 签名不同，官方包会安装失败 |

---

## 改了什么

一共 **3 处代码改动**（基础版），全部集中在"是否允许内嵌显示"这一条路径上，
不涉及任何咖啡机通信、数据处理或界面渲染逻辑。

| # | 文件 | 改动 |
|---|---|---|
| 1 | `lib/src/services/webview_compatibility_checker.dart` | 跳过启动时的 WebView 自检（含渲染测试和部分厂商的固定延迟） |
| 2 | `lib/src/app.dart` | 不再因 `sdkInt < 31` 置降级标志 |
| 3 | `lib/src/app.dart` | 引导结束后正常打开皮肤，而非停在浏览器引导卡片 |

> 补丁 1 是可选的加速项：自检的真实 SDK 门槛是 29，Android 11 本来能通过。
> 去掉它可以缩短启动时间，也避免个别机型在渲染测试上偶发误判。
> 真正起决定作用的是补丁 2 和 3。

改完后启动日志会打印：

```
PATCHED: Android SDK 30 - degraded mode DISABLED
```

**除此之外没有任何修改。** 补丁脚本 `patch-android11.sh` 里每处改动都有完整注释，
可以直接阅读核对。

可选：加 `--with-ota` 会额外改 8 处，把 App 内更新指向本仓库并支持同版本重构建识别。
默认不启用，详见 `README-OTA.md`。

---

## 安装

从 [Releases](https://github.com/UncleIce/decaid-android11/releases) 下载
`decaid-android11-<版本>-arm64.apk`。

```bash
adb install -r decaid-android11-0.9.2-arm64.apk
```

| 情况 | 是否需要卸载 | 数据 |
|---|---|---|
| 已装本 fork 的旧版本 | 不需要，直接覆盖 | 保留 |
| 已装官方 Decaid | **必须卸载** | **可完整迁移**，卸载前先导出备份 |

原因：两者签名不同（本 fork `953a1ad5…`，官方 `f4ae824f…`），
Android 不允许签名不同的包互相升级。

> ⚠️ **从官方版切换前请务必先导出备份。**
> 数据存在应用私有目录（`/data/data/net.tadel.reaprime/`），
> 卸载会一并删除。但只要先导出备份，装好新版后导入即可完整恢复。
> 详细步骤见 [`从官方版迁移.md`](从官方版迁移.md)。

### 快速迁移（三步）

```
① 导出   浏览器打开 http://<平板IP>:8080 → Settings → Data → Backup → Export
② 卸载   adb uninstall net.tadel.reaprime
③ 导入   装好新版 → Settings → Data → Backup → Import
```

前提：官方版会拦截界面，需用**浏览器**访问 8080 端口操作导出。

> 皮肤（skins）是插件形式，不在备份内，需重新安装。

---

## 版本号规则

| 上游 | 本仓库 | App 内显示 |
|---|---|---|
| `v0.9.2` | `android11-v0.9.2` | `0.9.2` |

tag 带 `android11-` 前缀，因为 fork 会继承上游全部 tag，同名会互相覆盖
（详见 `维护手册.md`）。App 内显示的版本号与上游一致，便于对照。

---

## 更新与维护

| 场景 | 你的操作 |
|---|---|
| 上游发布新版本 | 通常无需操作，自动跟进 |
| 补丁失效（上游改代码） | 收到 Issue 通知，按 `维护手册.md` 修复 |
| 想立即发布某版本 | Actions → Sync Upstream → 填 `force_version` |

自动同步每天运行一次，流程是：检测上游新 tag → 验证补丁可应用 → 应用并提交 → 打 tag → 编译 → 发布 Release。

---

## 许可

本项目与上游同为 **GPL-3.0**，`LICENSE.txt` 未作修改。

| 义务 | 本仓库做法 |
|---|---|
| 公开源码 | 仓库公开，含完整补丁脚本 |
| 保留版权声明 | `LICENSE.txt` 原样保留 |
| 标明修改 | 代码里标注 `PATCHED`，README 列出全部改动 |
| 相同许可分发 | 保持 GPL-3.0 |
| 不冒充官方 | 各处以"非官方构建"标明 |

由于 GPL-3.0 要求分发修改版时提供对应源码，本仓库公开即为满足。

---

## 上游项目

功能和文档请看上游：

- 仓库：https://github.com/decentespresso/decaid
- Releases：https://github.com/decentespresso/decaid/releases
- Issues：https://github.com/decentespresso/decaid/issues

**上游能用的情况下请优先用官方版本。** 本 fork 只对旧版 Android 有意义，
如果上游哪天自己支持了 Android 11，这个项目就应该退休
（判断方法见 `维护手册.md` 第八节）。

---

## 下面是完整的搭建与维护文档


## 这个包里的文件

| 文件 | 用途 | 放到仓库哪 |
|---|---|---|
| `patch-android11.sh` | 补丁脚本（默认基础版，加 `--with-ota` 启用 OTA） | 仓库根目录 |
| `keystore.b64` | 签名密钥的 base64 | **不提交**，填到 GitHub Secrets |
| `android11-release.yml` | 编译发布 workflow（基础版） | `.github/workflows/` |
| `android11-release-ota.yml` | 编译发布 workflow（OTA 版） | 二选一 |
| `sync-upstream.yml` | 自动跟进上游 workflow | `.github/workflows/` |
| `README-OTA.md` | OTA 详细说明（第二阶段） | — |
| `维护手册.md` | 日常维护、故障排查、退休判断 | — |
| `README.md` | 本文件 | — |

**一个脚本两种模式**：

```bash
./patch-android11.sh                 # 基础版：3 处补丁，只解决内嵌显示
./patch-android11.sh --with-ota      # OTA 版：11 处补丁，额外让 App 内可更新
```

建议先用基础版跑通 CI，稳定后再切 OTA（详见 `README-OTA.md`）。

---

## 阶段 1：创建 fork（10 分钟）

### 1.1 Fork 上游仓库

打开 https://github.com/decentespresso/decaid

点右上角 **Fork** → Repository name 填 **`decaid-android11`** → **Create fork**

> ⚠️ 不要勾选 "Copy the main branch only"，需要完整历史（`flutter_with_commit.sh` 依赖 git tag）

### 1.2 克隆到本地

```bash
git clone https://github.com/UncleIce/decaid-android11.git
cd decaid-android11
git remote add upstream https://github.com/decentespresso/decaid.git
git fetch upstream --tags
```

### 1.3 建补丁分支

```bash
# 基于上游最新稳定版
LATEST=$(git tag -l 'v*' --sort=-v:refname | grep -vE 'beta|alpha|rc' | head -1)
echo "基线版本: $LATEST"

git checkout -b android11 "upstream/main"

# 放入补丁脚本
cp /path/to/patch-android11.sh .
chmod +x patch-android11.sh

# 验证能打补丁
DRY_RUN=1 ./patch-android11.sh .
```

期望输出：

```
[✓] 补丁1 跳过WebView自检：可应用（DRY RUN 未写入）
[✓] 补丁2 取消降级标志：可应用（DRY RUN 未写入）
[✓] 补丁3 强制打开皮肤：可应用（DRY RUN 未写入）
[✓] DRY RUN 通过：3 处补丁均可应用
```

### 1.4 实际应用并提交

```bash
./patch-android11.sh .

# 清理备份文件，不提交
rm -f lib/src/app.dart.orig lib/src/services/webview_compatibility_checker.dart.orig

git add -A
git commit -m "feat(android11): 支持 Android 11 内嵌显示 WebUI"
git push -u origin android11
```

---

## 阶段 2：配置 GitHub 仓库（15 分钟）

### 2.1 添加签名密钥

**生成 base64**（`keystore.b64` 文件内容，或自己生成）：

```bash
base64 -w0 decaid-release.jks > keystore.b64
cat keystore.b64
```

**填入 GitHub**：

1. 仓库页 → **Settings** → 左侧 **Secrets and variables** → **Actions**
2. 点 **New repository secret**
3. Name: `ANDROID_KEYSTORE_B64`
4. Secret: 粘贴 `keystore.b64` 的**全部内容**（约 3536 字符，一长串无换行）
5. **Add secret**

> ⚠️ 这是最关键的一步。用错密钥，用户升级时会遇到
> `INSTALL_FAILED_UPDATE_INCOMPATIBLE`，只能卸载重装、数据丢失。

### 2.2 添加签名指纹变量

1. 同一页面点 **Variables** 标签
2. **New repository variable**
3. Name: `EXPECTED_SIGNATURE`
4. Value:
   ```
   953a1ad56b0f95f79d67d0dad5f41b641180e68989e7678cef13fbb97b39e1c2
   ```
5. **Add variable**

> 这个值用于 CI 校验，防止误用其它密钥。

### 2.3 开启 Actions 写权限

**Settings** → **Actions** → **General** → 拉到底 **Workflow permissions**

- 选 **Read and write permissions**
- 勾选 **Allow GitHub Actions to create and approve pull requests**
- **Save**

### 2.4 验证密钥正确

```bash
# 本地核对，确认和上面填的一致
keytool -list -v -keystore decaid-release.jks \
  -storepass android -alias androiddebugkey | grep SHA256
# 应输出 95:3A:1A:D5:...
```

---

## 阶段 3：添加 workflows（5 分钟）

```bash
mkdir -p .github/workflows
cp /path/to/android11-release.yml .github/workflows/
cp /path/to/sync-upstream.yml .github/workflows/

git add .github/workflows/
git commit -m "ci: 添加 Android 11 自动构建与上游同步"
git push
```

---

## 阶段 4：首次构建验证（15 分钟）

### 4.1 手动触发

仓库页 → **Actions** → 左侧 **Android 11 Build & Release** → **Run workflow**

- Branch: `android11`
- tag: `v0.9.2`（或上游当前最新稳定版；前缀 `android11-` 会自动补上）
- **Run workflow**

### 4.2 观察日志

三个 job 依次执行：

| Job | 期望结果 | 耗时 |
|---|---|---|
| 预检补丁 | ✓ 3 处补丁可应用 | ~20 秒 |
| 编译 APK | ✓ 签名核验通过 | ~16 分钟 |
| 发布 Release | 手动触发时**跳过** | — |

**必须确认的日志**：

```
✓ 补丁已编入产物
APK 签名: 953a1ad56b0f95f79d67d0dad5f41b641180e68989e7678cef13fbb97b39e1c2
```

### 4.3 下载产物验证

Actions 页面底部 → **Artifacts** → `android11-apk` → 下载

```bash
unzip android11-apk.zip
ls -la out/
# decaid-android11-0.9.2-arm64.apk
# decaid-android11-0.9.2-arm64.apk.sha256

# 本地验签
apksigner verify --print-certs out/*.apk | grep SHA-256
```

### 4.4 装到平板验证

```bash
adb install -r out/decaid-android11-0.9.2-arm64.apk
```

**应该直接覆盖安装成功**（签名与你平板上现有的 `953a1ad5` 一致）。

打开 App，确认：

```bash
adb logcat -d | grep flutter | grep PATCHED
# 期望: PATCHED: Android SDK 30 - degraded mode DISABLED
```

界面应直接显示咖啡机皮肤，无「去浏览器打开」提示。

---

## 阶段 5：发布正式版本（5 分钟）

首次构建验证通过后，打 tag 发布：

```bash
git checkout android11

# tag 带 android11- 前缀，与上游 v* 隔离
git tag -a android11-v0.9.2 -m "Android 11 适配版 v0.9.2（基于上游 v0.9.2）"
git push origin android11-v0.9.2
```

> **为什么加前缀**：fork 会继承上游全部 78 个稳定版 tag。
> 若与上游同名，`git fetch upstream --tags --force` 会把你已发布的 tag
> 强制指回上游未打补丁的提交，导致同步逻辑误判并无限重复构建。

这会自动触发完整流水线：预检 → 编译 → **发布 Release**。

Release 页面会出现：

```
标题: android11-v0.9.2 — Android 11 适配版
文件: decaid-android11-0.9.2-arm64.apk
      decaid-android11-0.9.2-arm64.apk.sha256
```

---

## 阶段 6：开启自动同步（1 分钟）

`sync-upstream.yml` 默认已启用（每天 UTC 02:00 = 北京时间 10:00）。

先手动跑一次确认：

```
Actions → Sync Upstream → Run workflow
  dry_run: ✓ 勾选（只检查不改动）
  force_version: 留空
```

看 **Summary** 里的输出：

| 项目 | 期望 |
|---|---|
| 上游版本 | `v0.9.3`（或当前最新） |
| 本仓库标签 | `android11-v0.9.3` |
| 需要构建 | `true` |
| 补丁兼容 | `true` |

**先跑 dry_run，确认无问题**，再去掉勾选跑正式同步。

---

## 日常维护

### 上游发新版时（全自动）

```
上游打 tag v0.9.3
      ↓ 最多 24 小时
sync-upstream 检测到
      ↓
验证补丁能应用
      ↓ 能
提交到 android11 分支 + 推同名 tag v0.9.3
      ↓
android11-release 自动构建发布
      ↓
用户在 Decaid 里看到更新提示（如果启用了 OTA）
```

**你什么都不用做。**

### 补丁失效时（需要人工）

收到 GitHub Issue（标签 `patch-broken`）：

```
标题: 补丁失效：上游 v0.9.3 需要人工适配
```

处理步骤：

```bash
# 1. 拉取上游新版本
git fetch upstream --tags
git checkout -b fix-v0.9.3 upstream/v0.9.3
cp patch-android11.sh .

# 2. 看哪一处失败
DRY_RUN=1 ./patch-android11.sh .

# 3. 定位新代码位置
grep -n 'sdkInt' lib/src/app.dart
grep -n 'degradedAndroid' lib/src/app.dart
grep -n 'Starting WebView compatibility' lib/src/services/webview_compatibility_checker.dart

# 4. 修改 patch-android11.sh 里对应的 old/new 字符串

# 5. 验证
./patch-android11.sh .     # 应全部成功

# 6. 提交
git add -A && git commit -m "fix: 适配 v0.9.3"
git push origin fix-v0.9.3
```

然后手动跑 **Sync Upstream**，指定 `force_version: v0.9.3`。

### 上游终于支持 Android 11 时

检查 `lib/src/app.dart`：

```bash
grep -n "sdkInt < " lib/src/app.dart
```

如果门槛从 `31` 变成了 `29` 或更低，说明**官方已支持**，本项目可以退休：

1. 在 README 顶部加说明「上游已支持，请用官方版」
2. 归档仓库，或直接删掉

---

## 排查常见问题

### 构建失败：`Gradle version lower than Flutter's minimum`

Flutter 版本被改了。确认 workflow 里：

```yaml
FLUTTER_VERSION: '3.47.9'
```

**不能**用 3.50（强制 Gradle 9.3.1+，项目锁定 8.14.3）。

### 构建失败：`密钥指纹不符`

- 检查 `ANDROID_KEYSTORE_B64` 是否完整复制（3536 字符）
- 检查 `EXPECTED_SIGNATURE` 是否为 `953a1ad5...`（全小写，无冒号）

### 构建失败：`补丁定位失败`

上游代码结构变了。按上面「补丁失效」流程处理。

### 产物装不上：`INSTALL_FAILED_UPDATE_INCOMPATIBLE`

签名不一致。

```bash
# 查 APK 签名
apksigner verify --print-certs your.apk | grep SHA-256

# 查平板已装签名
adb shell "dumpsys package net.tadel.reaprime | grep signatures"
```

两者必须一致。若不一致，说明 `ANDROID_KEYSTORE_B64` 填错了。

### Release 没有自动创建

- 检查 tag 是否是 `android11-v*` 格式（只有这个模式会触发）
- 检查是否手动触发（`workflow_dispatch` 不发布，只有 tag 才发布）
- 检查 `Settings → Actions → Workflow permissions` 是否 Read and write

---

## 关于 OTA

默认（基础版）**没有改 OTA 逻辑**，因此：

| 场景 | 结果 |
|---|---|
| App 内自动更新 | 指向官方仓库，下载的包签名不符，**装不上** |
| 建议 | 保持 `automaticUpdateCheck: false`，手动下载新版覆盖安装 |

### 如果要启用 OTA

用 `--with-ota` 重跑补丁脚本，再换用 `android11-release-ota.yml`。
它会改 4 处数据源（指向本仓库）+ 4 处版本比较逻辑（识别同版本重构建）。

核心难点与完整步骤见 `README-OTA.md`。

**建议先把当前流程跑稳一两个版本，再考虑加 OTA。**

---

## 附录：版本号是怎么进来的

`flutter_with_commit.sh` 从 git tag 推导版本并注入：

```bash
TAG=$(git describe --tags --abbrev=0)
VERSION="${TAG#v}"                              # v0.9.2 → 0.9.2
BUILD_NUMBER=$(git rev-list --count origin/main)
--dart-define=VERSION="$VERSION"
--dart-define=BUILD_NUMBER="$BUILD_NUMBER"
```

> ⚠️ 注意它只剥 `v` 前缀。如果你的 tag 是 `android11-v0.9.2`，
> 它会算出 `android11-v0.9.2` 这个**非法版本号**（App 用 pub_semver 比较会出错）。
>
> 所以 workflow 在编译前会先补一个纯 semver 的本地 tag：
>
> ```bash
> git tag -f "v$VERSION" HEAD      # v0.9.2 指向当前提交
> ```
>
> 这样 `git describe` 取到的是 `v0.9.2`，不必修改上游脚本。
> 这个本地 tag 只在 CI 的临时工作区里存在，不会推送。

所以**必须用 `flutter_with_commit.sh` 编译**，直接 `flutter build apk`
会导致 `BuildInfo.version` 是 pubspec 默认的 `1.0.0`。

workflow 里已处理（优先用该脚本，找不到才降级）。
