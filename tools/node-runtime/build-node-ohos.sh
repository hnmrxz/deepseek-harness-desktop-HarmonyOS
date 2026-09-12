#!/usr/bin/env bash
# 交叉编译 Node.js（OpenHarmony aarch64）→ libnode.so + node
#
# 依据（都已核实）：
#   - Node 官方 BUILDING.md 的平台表列 OpenHarmony/arm64（Experimental）
#   - v22.23.2 的 common.gypi 里确有 `OS=="openharmony"` 分支（在 tag 上核对过）
#   - `--dest-os` 的合法取值是 openharmony（不是 ohos）
#   - 版本下限：OHOS 支持 >= 22.17.0；会话持久化的 zstd 需要 >= 22.15 ⇒ 取 v22.23.2
#   - `--shared` 在 OpenHarmony 上属官方"未测试"路径（D6 E12）——本脚本就是去证伪/证实它
#
# 产物（关键）：
#   out/Release/libnode.so.<n>   ← 端侧要的"能被 HAP 加载的 Node"
#   out/Release/node             ← 同一次构建的副产品，可用于 HNP 路线
#
# 用法：bash 02-build-node.sh
# 说明：会先等 01-fetch-sdk.sh 把 SDK 放好（轮询），因此可以并行启动。
set -euo pipefail

NODE_VER="${NODE_VER:-v22.23.2}"
ROOT="${HOME}/ohos"
SDK="${ROOT}/sdk"
CLANG_DIR="${SDK}/native/llvm/bin"
CLANG="${CLANG_DIR}/aarch64-unknown-linux-ohos-clang"
SYSROOT="${SDK}/native/sysroot"
SRC_DIR="${ROOT}/node-${NODE_VER}"
BUILD_LOG="${ROOT}/build-node.log"
# 说明：SRC_DIR 必须在 ${ROOT} 下——解包发生在 ${ROOT}（见下），
# 曾经写成 ${HOME}/node-<ver> 导致 cd 到不存在的目录（实测踩过）

echo "[node] 等待 SDK 就绪（${CLANG}）"
for i in $(seq 1 240); do
  [ -x "${CLANG}" ] && break
  sleep 15
done
if [ ! -x "${CLANG}" ]; then
  echo "[node] ✗ 等待 SDK 超时（40 分钟）"
  exit 1
fi
echo "[node] ✓ SDK 就绪"

cd "${ROOT}"

# ── 取源码（用官方源码包，比 clone 快且不带历史）──
if [ ! -d "${SRC_DIR}" ]; then
  TARBALL="node-${NODE_VER}.tar.xz"
  if [ ! -s "${TARBALL}" ]; then
    echo "[node] 下载源码 ${NODE_VER}"
    # -sS：不打印进度条。进度条走 stderr 会让调用方（PowerShell）报 NativeCommandError，
    # 把整个任务判成失败，从而掩盖真实结果（实测踩过）
    curl -fsSL --retry 5 -o "${TARBALL}" "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}.tar.xz"
  fi
  echo "[node] 解包源码 → ${ROOT}"
  tar -xf "${TARBALL}"
fi
cd "${SRC_DIR}"

# ── 配置 ──
# -fno-emulated-tls：OHOS 工具链的 ABI 要求（来自 Node OHOS 移植维护者的 CI 用法）
export CC="${CLANG} -fno-emulated-tls"
export CXX="${CLANG_DIR}/aarch64-unknown-linux-ohos-clang++ -fno-emulated-tls"
# 交叉编译时宿主工具用系统 gcc/g++
export CC_host="gcc"
export CXX_host="g++"
export AR_host="ar"
export LD="${CLANG_DIR}/ld.lld"
export LDFLAGS="-fuse-ld=lld"

echo "[node] configure（dest-os=openharmony dest-cpu=arm64 --shared）"
./configure \
  --dest-os=openharmony \
  --dest-cpu=arm64 \
  --cross-compiling \
  --openssl-no-asm \
  --shared \
  --prefix="${ROOT}/node-install" \
  2>&1 | tee -a "${BUILD_LOG}"

echo "[node] make -j$(nproc)（V8 很重，预计 30~90 分钟）"
make -j"$(nproc)" 2>&1 | tee -a "${BUILD_LOG}"

echo "[node] ── 产物 ──"
ls -la out/Release/ 2>/dev/null | grep -E 'libnode|^.*node$|\.so' || ls -la out/Release/ | head -30
echo "[node] ── 交叉产物 ELF 校验 ──"
READELF="${CLANG_DIR}/llvm-readelf"
for f in out/Release/libnode.so* out/Release/node; do
  [ -e "$f" ] || continue
  echo "--- $f"
  "${READELF}" -h "$f" | grep -E 'Class|Machine|Type' || true
  "${READELF}" -S "$f" | grep -E '\.codesign|\.note\.ohos' || echo "    （无 ohos 签名段：需要自行签名）"
done
echo "[node] 完成（日志 ${BUILD_LOG}）"
