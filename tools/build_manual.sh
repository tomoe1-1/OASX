#!/usr/bin/env bash
# 手工构建 OASX-Neo 的 app.so（绕过 flutter CLI）
#
# 背景：本机环境全局禁止 Dart 创建子进程，`flutter build` 会崩在
# ProcessException，因此手工走 frontend_server → gen_snapshot 两步。
#
# ⚠️ 三个必须踩对的坑（踩错的表现是「进程活着但窗口永不显示」）：
#
#   1. 必须带 --source <registrant> + -Dflutter.dart_plugin_registrant=<URI>，
#      否则 Dart 侧插件（path_provider_windows / shared_preferences_windows 等）
#      不注册，main() 里的 GetStorage.init() 抛 MissingPluginException，
#      runApp() 永不执行 → 首帧不存在 → runner 的 SetNextFrameCallback 不触发 →
#      窗口停在 SW_HIDE。
#
#   2. 该 URI 必须是 `file:///C:/...` 形式（不是 Windows 反斜杠路径）。
#      引擎用 String.fromEnvironment 取值后按 URI 解析库，反斜杠解析不出。
#
#   3. gen_snapshot 用 windows-x64-release/ 下的那份，并带 --deterministic。
#
# 用法： bash tools/build_manual.sh
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../src" && { cygpath -m "$PWD" 2>/dev/null || pwd; })"
FLUTTER="${FLUTTER_ROOT:-$HOME/.workbuddy/toolchains/flutter}"

# 托管 venv 里的 Python（装了 Pillow 等构建/复核脚本的依赖）。
# 不用裸 `python`：系统 PATH 上没有可靠的同名解释器。
PYTHON_BIN="${PYTHON_BIN:-$HOME/.workbuddy/binaries/python/envs/default/Scripts/python.exe}"

DARTAOT="$FLUTTER/bin/cache/dart-sdk/bin/dartaotruntime.exe"
FRONTEND="$FLUTTER/bin/cache/artifacts/engine/windows-x64/frontend_server_aot.dart.snapshot"
PATCHED_SDK="$FLUTTER/bin/cache/artifacts/engine/common/flutter_patched_sdk_product"
GEN_SNAPSHOT="$FLUTTER/bin/cache/artifacts/engine/windows-x64-release/gen_snapshot.exe"

cd "$SRC"
mkdir -p build

# 生成 dart_plugin_registrant.dart（无 flutter CLI 时从插件清单手工推导）
REG_FILE="$SRC/.dart_tool/flutter_build/dart_plugin_registrant.dart"
if [ ! -f "$REG_FILE" ]; then
  echo "!! 缺少 $REG_FILE" >&2
  echo "   该文件由 'flutter pub get' + 'flutter build' 生成，" >&2
  echo "   可从同版本完整构建过的工程复制（内容仅取决于插件清单）。" >&2
  exit 1
fi

# 关键：file:/// 形式的 URI。
# 注意用 cygpath -m 转成 C:/... 形式 —— Git Bash 下 $PWD 是 /c/... 的 MSYS
# 路径，直接拼进 URI 会变成 file:////c/... 导致「找不到网络路径」。
if command -v cygpath >/dev/null 2>&1; then
  REG_WIN="$(cygpath -m "$REG_FILE")"          # C:/Users/.../dart_plugin_registrant.dart
else
  REG_WIN="${REG_FILE//\\//}"
fi
REG_URI="file:///$REG_WIN"
echo "registrant URI: $REG_URI"

echo "[1/2] Dart → kernel"
"$DARTAOT" "$FRONTEND" \
  --sdk-root "$PATCHED_SDK/" \
  --target=flutter \
  --no-print-incremental-dependencies \
  -Ddart.vm.profile=false \
  -Ddart.vm.product=true \
  --delete-tostring-package-uri=dart:ui \
  --delete-tostring-package-uri=package:flutter \
  --aot \
  --tfa \
  --target-os windows \
  --packages=.dart_tool/package_config.json \
  --source="$REG_URI" \
  --source=package:flutter/src/dart_plugin_registrant.dart \
  -Dflutter.dart_plugin_registrant="$REG_URI" \
  --output-dill=build/app.dill \
  lib/main.dart

echo "[2/2] kernel → app.so"
"$GEN_SNAPSHOT" \
  --deterministic \
  --snapshot_kind=app-aot-elf \
  --elf=build/app.so \
  --strip \
  build/app.dill

echo
echo "完成：$SRC/build/app.so"
ls -la build/app.so

# ---- 部署到运行目录 ----
#
# ⚠️ 这里以前只写了一句 `echo "部署： cp ..."` —— 把命令当提示打印了，
# 实际没执行。结果是「构建成功」但运行目录仍是旧产物，改了代码看不到效果，
# 极难排查。现在改成真的拷。
#
# ⚠️ 第二个坑（2026-09-30 踩到）：本工程有**两个**真实运行目录，
# 只拷一个就会「构建成功但用户那边毫无变化」：
#   ① OASX-Neo/data/                                 根目录运行版
#   ② OASX-Neo/build/windows/x64/runner/Release/data/ 构建目录版（用户常点这个）
# exe 只认自己**同级**的 data/，两份内容必须一起更新。
echo
echo "[3/3] 部署到运行目录"
ROOT="$(cd "$SRC/.." && { cygpath -m "$PWD" 2>/dev/null || pwd; })"
DSTS=("$ROOT/data")
BUILD_RUN="$ROOT/build/windows/x64/runner/Release/data"
if [ -d "$BUILD_RUN/flutter_assets" ]; then
  DSTS+=("$BUILD_RUN")
fi

for D in "${DSTS[@]}"; do
  cp -f build/app.so "$D/app.so"
  # 资源也要同步：flutter build 会把 assets 摊到 data/flutter_assets/，
  # 手工链没有这一步，新增/修改的资源必须手工镜像过去，
  # 否则运行时 rootBundle.load() 会抛 asset not found。
  if [ -d "$D/flutter_assets/assets" ]; then
    cp -rf assets/. "$D/flutter_assets/assets/"
    echo "已同步 assets/ → ${D#$ROOT/}/flutter_assets/assets/"
  else
    echo "警告：$D/flutter_assets/assets 不存在，资源未同步" >&2
  fi
done

# AssetManifest.bin 按 pubspec 的 assets 段重建（引擎只读 .bin）。
# 只生成一次，其余运行目录复用同一份 —— 构建目录里那份旧 .bin 是
# 另一种格式，sync_asset_manifest.py 解析它会抛「未支持的 tag」。
"$PYTHON_BIN" "$SRC/../tools/sync_asset_manifest.py" "${DSTS[0]}/flutter_assets"
for D in "${DSTS[@]:1}"; do
  cp -f "${DSTS[0]}/flutter_assets/AssetManifest.bin" "$D/flutter_assets/AssetManifest.bin"
done

echo
for D in "${DSTS[@]}"; do
  echo "校验 ${D#$ROOT/}:"
  md5sum build/app.so "$D/app.so"
done
