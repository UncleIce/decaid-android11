# Decaid fork 搭建手册

> 目标：让 Decaid 在 Android 11 上内嵌显示界面，并自动跟进上游新版本、自动编译发布。
>
> 仓库：https://github.com/UncleIce/decaid-android11
> 基线：https://github.com/decentespresso/decaid （GPL-3.0）

---

## 这个包里的文件

| 文件 | 用途 | 放到仓库哪 |
|---|---|---|
| `patch-android11.sh` | 补丁脚本（默认基础版，加 `--with-ota` 启用 OTA） | 仓库根目录 |
| `keystore.b64` | 签名密钥的 base64 | **不提交**，填到 GitHub Secrets |
| `android11-release.yml` | 编译发布 workflow（基础版） | `.github/workflows/` |
| `android11-release-ota.yml` | 编译发布 workflow（OTA 版） | 二选一 |
| `sync-upstream.yml` | 自动跟进上游 workflow | `.github/workflows/` |
| `README-OTA.md` | OTA 详细说明（第二阶段） | — |
| `README.md` | 本手册 | — |

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

- 检查 tag 是否 `v` 开头
- 检查是否手动触发（`workflow_dispatch` 不发布，只有 tag 才发布）
- 检查 `Settings → Actions → Workflow permissions` 是否 Read and write

---

## 关于 OTA

**当前版本没有改 OTA 逻辑**，因此：

| 场景 | 结果 |
|---|---|
| App 内自动更新 | 指向官方仓库，下载的包签名不符，**装不上** |
| 建议 | 保持 `automaticUpdateCheck: false`，手动下载新版覆盖安装 |

### 如果要启用 OTA

需要 4 处补丁（改数据源指向你的 fork）+ 1 处版本比较逻辑改动。详见
`04-签名与数据.md` 或联系我补充。核心难点：

- tag 用上游原样（`v0.9.3`）时，版本号与本地相同 → OTA 判定"无更新"
- 需要额外比较 `BUILD_NUMBER` 才能识别同版本的重构建

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
