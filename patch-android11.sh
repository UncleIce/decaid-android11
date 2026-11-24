#!/usr/bin/env bash
# =============================================================================
# Decaid Android 11 适配补丁（统一版）
# =============================================================================
#
# 仓库: https://github.com/UncleIce/decaid-android11
# 基线: decentespresso/decaid (GPL-3.0)
#
# -----------------------------------------------------------------------------
# 这个脚本干什么
# -----------------------------------------------------------------------------
#   解除 Decaid「必须 Android 12+ (SDK 31) 才内嵌显示 WebUI」的限制，
#   让 Android 11 (SDK 30) 设备在 App 内部直接显示咖啡机界面。
#
#   根因（源码 app.dart）：
#     if (mounted && info.version.sdkInt < 31) { _degradedAndroid = true; }
#     ...
#     if (!supportedPlatforms || _degradedAndroid) return;   // 不打开皮肤
#   → 界面停在「去浏览器打开」卡片。SDK 30 只差 1，短路这两处即可。
#
# -----------------------------------------------------------------------------
# 两种模式
# -----------------------------------------------------------------------------
#   默认（基础版）    3 处补丁，只解决内嵌显示
#   --with-ota       11 处补丁，额外让 OTA 可用
#
#   基础版适合：先跑通 CI、验证编译链路
#   OTA 版适合：已经稳定出包，想让 App 内自动更新
#
#   OTA 为什么需要额外补丁：
#     1. 数据源写死 tadelv/reaprime（= 官方仓库）
#        → 下载官方 APK，签名 f4ae824f ≠ 本地 953a1ad5 → 安装失败
#     2. tag 用上游原样 v0.9.2，本地版本也是 0.9.2
#        → 版本相等，判定「已是最新」，不提示
#
#     补丁 4-6 解决第 1 点（改数据源）
#     补丁 7a-7e 解决第 2 点（版本相同时比 build number）
#
# -----------------------------------------------------------------------------
# 用法
# -----------------------------------------------------------------------------
#   ./patch-android11.sh                     基础版，作用于当前目录
#   ./patch-android11.sh /path/to/src        指定源码目录
#   ./patch-android11.sh --with-ota          基础版 + OTA
#   DRY_RUN=1 ./patch-android11.sh --with-ota   只检查，不写文件
#
#   OTA 数据源默认 UncleIce/decaid-android11，
#   可通过环境变量覆盖：
#     GITHUB_OWNER=xxx GITHUB_REPO=yyy ./patch-android11.sh --with-ota
#
# -----------------------------------------------------------------------------
# 退出码
# -----------------------------------------------------------------------------
#   0 = 补丁全部成功（或 DRY RUN 全部可应用）
#   1 = 源码结构已变，需人工适配
#
# -----------------------------------------------------------------------------
# 许可
# -----------------------------------------------------------------------------
#   Decaid 是 GPL-3.0。本脚本及其产出的修改同样遵循 GPL-3.0。
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
WITH_OTA=0
SRC="."
for arg in "$@"; do
  case "$arg" in
    --with-ota|--ota) WITH_OTA=1 ;;
    -h|--help)
      sed -n '3,60p' "$0" | sed 's/^# \?//'
      exit 0 ;;
    -*)
      echo "未知参数: $arg（用 --help 查看用法）" >&2
      exit 2 ;;
    *) SRC="$arg" ;;
  esac
done

DRY_RUN="${DRY_RUN:-0}"
GITHUB_OWNER="${GITHUB_OWNER:-UncleIce}"
GITHUB_REPO="${GITHUB_REPO:-decaid-android11}"

RED='\033[0;31m'; GRN='\033[0;32m'; YEL='\033[0;33m'; CYA='\033[0;36m'; NC='\033[0m'
info() { echo -e "${GRN}[✓]${NC} $*"; }
warn() { echo -e "${YEL}[!]${NC} $*"; }
fail() { echo -e "${RED}[✗]${NC} $*" >&2; }
head2() { echo; echo -e "${CYA}######## $* ########${NC}"; }

cd "$SRC"
if [ ! -f lib/src/app.dart ]; then
  fail "找不到 Decaid 源码: $PWD/lib/src/app.dart"
  exit 1
fi

MODE_NAME="基础版"
[ "$WITH_OTA" = "1" ] && MODE_NAME="OTA 版"

info "源码目录: $PWD"
info "补丁模式: $MODE_NAME"
[ "$WITH_OTA" = "1" ] && info "OTA 数据源: $GITHUB_OWNER/$GITHUB_REPO"
[ "$DRY_RUN" = "1" ] && warn "DRY RUN 模式：不会写入任何文件"

P_OK=0
P_FAIL=0
# 记录所有改动过的文件，最后输出摘要
TOUCHED=()

# -----------------------------------------------------------------------------
# 工具函数：精确替换，定位失败即记为失败（不中断，最后统一报错）
# -----------------------------------------------------------------------------
# $1 文件  $2 旧串  $3 新串  $4 补丁名  $5 幂等标记（补丁后才会出现的唯一串）
# $6 排查提示（可选）
apply_patch() {
  local file="$1" old="$2" new="$3" name="$4" marker="$5" hint="${6:-}"

  if [ ! -f "$file" ]; then
    fail "$name：文件不存在 → $file"
    P_FAIL=$((P_FAIL + 1))
    return 1
  fi

  # 已打过（幂等）—— 必须用补丁独有的标记串，
  # 不能用 new 的首行：那往往是原代码里本来就有的上下文行，会误判
  if grep -qF "$marker" "$file" 2>/dev/null; then
    warn "$name：已应用，跳过"
    P_OK=$((P_OK + 1))
    return 0
  fi

  if ! grep -qF "$old" "$file"; then
    fail "$name：定位失败，源码结构已变"
    echo "      文件: $file" >&2
    echo "      期望找到:" >&2
    echo "$old" | head -3 | sed 's/^/        | /' >&2
    [ -n "$hint" ] && echo "      排查: $hint" >&2
    P_FAIL=$((P_FAIL + 1))
    return 1
  fi

  if [ "$DRY_RUN" = "1" ]; then
    info "$name：可应用（DRY RUN 未写入）"
    P_OK=$((P_OK + 1))
    return 0
  fi

  [ -f "$file.orig" ] || cp "$file" "$file.orig"

  if ! python3 - "$file" "$old" "$new" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()
if old not in s:
    print(f"定位失败，源码中找不到期望的代码块: {path}", file=sys.stderr)
    sys.exit(1)
open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  then
    fail "$name：写入失败"
    P_FAIL=$((P_FAIL + 1))
    return 1
  fi

  info "$name：已应用"
  P_OK=$((P_OK + 1))
  TOUCHED+=("$file")
  return 0
}

# =============================================================================
# 第 1 部分：内嵌显示补丁（两种模式都应用）
# =============================================================================
head2 "第 1 部分：内嵌显示"

# -----------------------------------------------------------------------------
# 补丁 1 —— 跳过 WebView 自检
# -----------------------------------------------------------------------------
# 原逻辑: 启动隐藏 WebView 加载测试页，验证 JS 执行/DOM/CSS gradient，10 秒超时。
#         慢设备容易超时被判「不兼容」，进而触发降级。
# 补丁后: checkCompatibility() 直接返回 compatible。
#
# 注: 该检查器真正的硬门槛是 sdkInt < 29，SDK 30 本来能过。
#     打这个补丁主要是省掉启动时那次容易超时的自检。
# -----------------------------------------------------------------------------
apply_patch \
  "lib/src/services/webview_compatibility_checker.dart" \
  "_log.info('Starting WebView compatibility check...');" \
  "// === PATCHED (UncleIce/decaid-android11): force embedded WebView ===
    // 跳过 WebView 自检，强制使用内嵌 WebView 显示界面。
    // 修改自 Decaid (GPL-3.0) https://github.com/decentespresso/decaid
    _log.warning('Compatibility check BYPASSED (patched build)');
    _cachedResult = const CompatibilityResult.compatible();
    return _cachedResult!;

    // ignore: dead_code
    _log.info('Starting WebView compatibility check...');" \
  "补丁1 跳过WebView自检" \
  "Compatibility check BYPASSED (patched build)" \
  "grep -n 'Starting WebView compatibility' lib/src/services/webview_compatibility_checker.dart" || true

# -----------------------------------------------------------------------------
# 补丁 2 —— 不置降级标志（核心）
# -----------------------------------------------------------------------------
# 原逻辑: sdkInt < 31 就把 _degradedAndroid 置 true。
# 补丁后: 保留日志便于确认，但短路判断，永不置位。
# -----------------------------------------------------------------------------
apply_patch \
  "lib/src/app.dart" \
  "      final info = await DeviceInfoPlugin().androidInfo;
      if (mounted && info.version.sdkInt < 31) {
        setState(() => _degradedAndroid = true);
      }" \
  "      final info = await DeviceInfoPlugin().androidInfo;
      // === PATCHED (UncleIce/decaid-android11) ===
      // 原逻辑：sdkInt < 31 即标记降级，不内嵌显示界面。
      // 改为：记录版本但不降级，强制内嵌 WebView。
      _log.info(
        'PATCHED: Android SDK \${info.version.sdkInt} - degraded mode DISABLED',
      );
      // ignore: dead_code
      if (false && mounted && info.version.sdkInt < 31) {
        setState(() => _degradedAndroid = true);
      }" \
  "补丁2 取消降级标志" \
  "degraded mode DISABLED" \
  "grep -n 'sdkInt < ' lib/src/app.dart" || true

# -----------------------------------------------------------------------------
# 补丁 3 —— 忽略降级标志，正常打开皮肤（核心）
# -----------------------------------------------------------------------------
# 原逻辑: _degradedAndroid 为真就 return，不调 openStartupSkin()，
#         界面停在 browser hero card（「去浏览器打开」）。
# 补丁后: 短路 _degradedAndroid，正常打开皮肤。
# -----------------------------------------------------------------------------
apply_patch \
  "lib/src/app.dart" \
  "    if (!supportedPlatforms || _degradedAndroid) {" \
  "    if (!supportedPlatforms || (false && _degradedAndroid)) {" \
  "补丁3 强制打开皮肤" \
  "false && _degradedAndroid" \
  "grep -n 'supportedPlatforms || ' lib/src/app.dart" || true

# =============================================================================
# 第 2 部分：OTA 补丁（仅 --with-ota）
# =============================================================================
if [ "$WITH_OTA" = "1" ]; then
  head2 "第 2 部分：OTA"

  # ---------------------------------------------------------------------------
  # 补丁 4 —— OTA 数据源（update_check_service.dart）
  # ---------------------------------------------------------------------------
  # 原: AndroidUpdater(owner: 'tadelv', repo: 'reaprime', rateLimit: ...,)
  # 改: 指向本 fork
  #
  # 注: credentials 参数在上游部分版本存在、部分不存在，
  #     故只匹配到 repo 行为止，兼容两种写法。
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/update_check_service.dart" \
    "           AndroidUpdater(
             owner: 'tadelv',
             repo: 'reaprime'," \
    "           AndroidUpdater(
             // === PATCHED (android11 OTA) ===
             // 原值 tadelv/reaprime（旧名，GitHub 重定向到 decentespresso/decaid）。
             // 改为本 fork，避免下载到签名不兼容的官方包。
             owner: '$GITHUB_OWNER',
             repo: '$GITHUB_REPO'," \
    "补丁4 OTA数据源(service)" \
    "owner: '$GITHUB_OWNER'," \
    "grep -n \"owner: '\" lib/src/services/update_check_service.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 5 —— OTA 数据源（app.dart）
  # ---------------------------------------------------------------------------
  # 实际代码是单行写法：
  #   final updater = AndroidUpdater(owner: 'tadelv', repo: 'reaprime');
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/app.dart" \
    "AndroidUpdater(owner: 'tadelv', repo: 'reaprime');" \
    "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO');" \
    "补丁5 OTA数据源(app)" \
    "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO')" \
    "grep -n 'AndroidUpdater(' lib/src/app.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 6 —— OTA 数据源（settings_view.dart）
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/settings/settings_view.dart" \
    "AndroidUpdater(owner: 'tadelv', repo: 'reaprime');" \
    "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO');" \
    "补丁6 OTA数据源(settings)" \
    "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO')" \
    "grep -n 'AndroidUpdater(' lib/src/settings/settings_view.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 7a —— UpdateInfo 增加 buildNumber 字段
  # ---------------------------------------------------------------------------
  # 为什么需要：_isNewerVersion 只收到两个版本字符串，拿不到 release 的
  # 其它信息。要让「同版本的重构建」也能识别，必须把构建号传进来。
  #
  # buildNumber 有默认值 0，不会破坏 debugForceUpdate 等既有构造点。
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/android_updater.dart" \
    "class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool isPrerelease;
  final String tagName;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isPrerelease,
    required this.tagName,
  });" \
    "class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final bool isPrerelease;
  final String tagName;
  // === PATCHED (android11 OTA) ===
  // 从 release name/body 解析出的构建号，用于区分「同版本的重构建」
  final int buildNumber;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.isPrerelease,
    required this.tagName,
    this.buildNumber = 0,
  });" \
    "补丁7a UpdateInfo加buildNumber" \
    "final int buildNumber;" \
    "grep -n 'class UpdateInfo' -A12 lib/src/services/android_updater.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 7b —— 从 release JSON 解析构建号
  # ---------------------------------------------------------------------------
  # 约定：release name 形如 "v0.9.2 (build 42)"
  #       正则 build[\s:]+(\d+)  (忽略大小写) 提取 42
  #       name 为空时回退到 body
  #
  # ★ workflow 里的 Release 名称必须符合这个格式，否则解析不到。
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/android_updater.dart" \
    "    return UpdateInfo(
      version: version,
      downloadUrl: apkAsset['browser_download_url'] as String,
      releaseNotes: json['body'] as String? ?? '',
      isPrerelease: json['prerelease'] as bool,
      tagName: tagName,
    );" \
    "    // === PATCHED (android11 OTA): 解析构建号 ===
    // 从 release name 里找 \"build 42\" 或 \"build:42\"，name 为空则找 body
    int buildNumber = 0;
    final nameStr = (json['name'] as String?) ?? '';
    final bodyStr = (json['body'] as String?) ?? '';
    final buildMatch = RegExp(r'build[\\s:]+(\\d+)', caseSensitive: false)
        .firstMatch(nameStr.isNotEmpty ? nameStr : bodyStr);
    if (buildMatch != null) {
      buildNumber = int.tryParse(buildMatch.group(1) ?? '') ?? 0;
    }

    return UpdateInfo(
      version: version,
      downloadUrl: apkAsset['browser_download_url'] as String,
      releaseNotes: json['body'] as String? ?? '',
      isPrerelease: json['prerelease'] as bool,
      tagName: tagName,
      buildNumber: buildNumber,
    );" \
    "补丁7b 解析buildNumber" \
    "buildNumber = int.tryParse" \
    "grep -n 'return UpdateInfo(' -A6 lib/src/services/android_updater.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 7c —— 比较逻辑加入 build number（核心）
  # ---------------------------------------------------------------------------
  # 原逻辑:
  #   return Version.parse(newVersion).compareTo(Version.parse(currentVersion)) > 0;
  #   → 版本相等返回 false → 判定「已是最新」
  #
  # 改后:
  #   版本不同 → 按 semver 比
  #   版本相同 → 比 build number
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/android_updater.dart" \
    "  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      return Version.parse(newVersion)
              .compareTo(Version.parse(currentVersion)) >
          0;
    } catch (e) {
      _log.warning('Error comparing versions: \$e');
      return false;
    }
  }" \
    "  // === PATCHED (android11 OTA) ===
  // 原逻辑只比版本号，导致「同版本重构建」永远收不到更新。
  // 改为：版本不同按 semver 比；版本相同则比 build number。
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final nv = Version.parse(newVersion);
      final cv = Version.parse(currentVersion);
      final cmp = nv.compareTo(cv);
      if (cmp != 0) return cmp > 0;

      // 版本相同 —— 用 build number 区分
      final remoteBuild = _pendingBuildNumber;
      final localBuild = int.tryParse(BuildInfo.buildNumber) ?? 0;
      if (remoteBuild > localBuild) {
        _log.info(
          'Same version \$newVersion but newer build: '
          'remote=\$remoteBuild local=\$localBuild',
        );
        return true;
      }
      return false;
    } catch (e) {
      _log.warning('Error comparing versions: \$e');
      return false;
    }
  }

  // 保存最近一次解析到的 release 的 build number，供 _isNewerVersion 使用
  int _pendingBuildNumber = 0;" \
    "补丁7c 比较逻辑加buildNumber" \
    "_pendingBuildNumber" \
    "grep -n '_isNewerVersion' -A10 lib/src/services/android_updater.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 7d —— 调用比较前记录 build number
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/android_updater.dart" \
    "      final updateInfo = matchingReleases.first;

      if (_isNewerVersion(updateInfo.version, currentVersion)) {" \
    "      final updateInfo = matchingReleases.first;

      // === PATCHED (android11 OTA): 记录本次 release 的构建号 ===
      _pendingBuildNumber = updateInfo.buildNumber;

      if (_isNewerVersion(updateInfo.version, currentVersion)) {" \
    "补丁7d 传递buildNumber" \
    "_pendingBuildNumber = updateInfo.buildNumber" \
    "grep -n 'matchingReleases.first' -A4 lib/src/services/android_updater.dart" || true

  # ---------------------------------------------------------------------------
  # 补丁 7e —— 补 BuildInfo 的 import
  # ---------------------------------------------------------------------------
  # 补丁 7c 用到 BuildInfo.buildNumber（编译期注入的本地构建号）
  # ---------------------------------------------------------------------------
  apply_patch \
    "lib/src/services/android_updater.dart" \
    "import 'package:reaprime/src/services/apk_installer.dart';" \
    "import 'package:reaprime/build_info.dart';
import 'package:reaprime/src/services/apk_installer.dart';" \
    "补丁7e 补BuildInfo导入" \
    "import 'package:reaprime/build_info.dart';" \
    "grep -n '^import' lib/src/services/android_updater.dart | head" || true
fi

# =============================================================================
# 结果汇总
# =============================================================================
echo

# --- DRY RUN：没有写文件，不能做内容校验，只看有没有定位失败 ---
if [ "$DRY_RUN" = "1" ]; then
  if [ "$P_FAIL" -gt 0 ]; then
    fail "DRY RUN：有 $P_FAIL 处无法应用，需人工适配"
    echo "::error::Decaid 源码结构已变，补丁失效。请更新 patch-android11.sh"
    exit 1
  fi
  info "DRY RUN 通过：$P_OK 处补丁均可应用（未写入任何文件，模式：$MODE_NAME）"
  exit 0
fi

# --- 实际校验：逐项确认标记串已在文件中 ---
echo "=== 校验 ==="
check() {
  if grep -qF "$2" "$1" 2>/dev/null; then
    info "$3 ✓"
  else
    fail "$3 ✗"
    P_FAIL=$((P_FAIL + 1))
  fi
}

check "lib/src/services/webview_compatibility_checker.dart" \
      "Compatibility check BYPASSED" "补丁1"
check "lib/src/app.dart" "degraded mode DISABLED"   "补丁2"
check "lib/src/app.dart" "false && _degradedAndroid" "补丁3"

if [ "$WITH_OTA" = "1" ]; then
  check "lib/src/services/update_check_service.dart" \
        "owner: '$GITHUB_OWNER'," "补丁4"
  check "lib/src/app.dart" \
        "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO')" "补丁5"
  check "lib/src/settings/settings_view.dart" \
        "AndroidUpdater(owner: '$GITHUB_OWNER', repo: '$GITHUB_REPO')" "补丁6"
  check "lib/src/services/android_updater.dart" "final int buildNumber;"          "补丁7a"
  check "lib/src/services/android_updater.dart" "buildNumber = int.tryParse"      "补丁7b"
  check "lib/src/services/android_updater.dart" "_pendingBuildNumber"            "补丁7c"
  check "lib/src/services/android_updater.dart" "_pendingBuildNumber = updateInfo.buildNumber" "补丁7d"
  check "lib/src/services/android_updater.dart" "import 'package:reaprime/build_info.dart';"   "补丁7e"
fi

echo
if [ "$P_FAIL" -gt 0 ]; then
  fail "失败 $P_FAIL 处，需人工适配"
  echo "::error::Decaid 源码结构已变，补丁失效。请更新 patch-android11.sh"
  exit 1
fi

info "全部补丁成功（$P_OK 处，模式：$MODE_NAME）"

# --- 功能小结 ---
echo
echo "✅ 内嵌显示：Android 11 可正常打开皮肤（补丁 1-3）"
if [ "$WITH_OTA" = "1" ]; then
  echo "✅ OTA 数据源：指向 $GITHUB_OWNER/$GITHUB_REPO（补丁 4-6）"
  echo "✅ 同版本识别：版本相同时比较 build number（补丁 7a-7e）"
  echo
  warn "编译时必须注入 VERSION 和 BUILD_NUMBER，否则 OTA 无法识别同版本更新："
  echo "     flutter build apk --release \\"
  echo "       --dart-define=VERSION=<版本> \\"
  echo "       --dart-define=BUILD_NUMBER=<递增构建号>"
  echo
  warn "Release 名称必须包含 build 号，格式如：v0.9.2 (build 42)"
else
  echo "ℹ️  OTA 未启用（基础版）。如需 App 内自动更新，用 --with-ota 重跑。"
fi

# --- 改动摘要，便于 CI 日志排查 ---
# 同一文件可能被多个补丁命中（如 app.dart 有 3 处），去重后再列
echo
info "改动摘要:"
printf '%s\n' "${TOUCHED[@]:-}" | awk 'NF && !seen[$0]++' | while read -r f; do
  [ -z "$f" ] && continue
  if [ -f "$f.orig" ]; then
    n=$(diff "$f.orig" "$f" 2>/dev/null | grep -c '^[<>]' || true)
    echo "  $(basename "$f"): ${n:-0} 行"
  fi
done

exit 0
