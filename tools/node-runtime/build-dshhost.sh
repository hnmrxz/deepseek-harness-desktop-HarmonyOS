#!/usr/bin/env bash
# Build the NAPI bootstrap module (libdshhost.so) that starts libnode.so in-process.
#
#   bash tools/node-runtime/build-dshhost.sh --compile-only   # 只编译，不需要 libnode.so.127
#   bash tools/node-runtime/build-dshhost.sh                  # 编译 + 链接（需要 libnode.so.127）
#
# Node 22.23.2 on OHOS exposes the runtime SONAME as libnode.so.127.
# Keep the runtime filename/SONAME explicit here; do not depend on a generic
# libnode.so symlink being present in the Node output directory.
#
# Why --compile-only exists: the C++ can be validated long before libnode.so.127 finishes
# linking. A compile-only pass catches every signature/header mistake; only the final
# link needs the Node library. Doing that first means the moment libnode.so.127 appears
# we are one command away from a module, instead of starting to debug C++ then.
#
# ASCII only.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
# shellcheck source=toolchain-env.sh
source "${HERE}/toolchain-env.sh" || exit 1

SRC="${NODE_SRC:-$HOME/ohos/node-v22.23.2}"
SRC_FILE="${REPO}/hostruntime/src/main/cpp/dshhost.cc"
OUT_DIR="${REPO}/entry/libs/arm64-v8a"
OUT_SO="${OUT_DIR}/libdshhost.so"
NODE_SONAME="libnode.so.127"
LIBNODE_DIR="${SRC}/out/Release"
LIBNODE="${LIBNODE_DIR}/${NODE_SONAME}"
COMPILE_ONLY=0
[ "${1:-}" = "--compile-only" ] && COMPILE_ONLY=1

CXX_OHOS="${OHOS_CLANG_DIR}/aarch64-unknown-linux-ohos-clang++"
READELF="${OHOS_CLANG_DIR}/llvm-readelf"

if [ ! -f "$SRC_FILE" ]; then
  echo "ERROR: source not found: $SRC_FILE" >&2
  exit 1
fi
for d in src deps/v8/include deps/uv/include; do
  if [ ! -d "$SRC/$d" ]; then
    echo "ERROR: missing include dir: $SRC/$d (need the Node source tree)" >&2
    exit 1
  fi
done

INCLUDES=(
  "-I$SRC/src"
  "-I$SRC/deps/v8/include"
  "-I$SRC/deps/uv/include"
)

# -fno-emulated-tls: OHOS ABI. -std=gnu++20: matches how we build Node itself.
# --sysroot/-D__MUSL__: musl-based OHOS target.
CFLAGS=(
  "--target=aarch64-linux-ohos"
  "--sysroot=${OHOS_SYSROOT}"
  "-D__MUSL__"
  "-fno-emulated-tls"
  "-std=gnu++20"
  "-fPIC"
  "-O2"
  "-Wall"
  # V8/Node 的头文件里有大量未使用参数，-Wextra 会把它们全刷出来，把真正的错误淹掉
  "-Wno-unused-parameter"
)

echo "[dshhost] compiling ${SRC_FILE#${REPO}/}"
if ! "$CXX_OHOS" "${CFLAGS[@]}" "${INCLUDES[@]}" -c "$SRC_FILE" -o /tmp/dshhost.o; then
  echo "[dshhost] ✗ 编译失败" >&2
  exit 1
fi
echo "[dshhost] ✓ 编译通过（$(stat -c%s /tmp/dshhost.o) 字节）"

if [ "$COMPILE_ONLY" = "1" ]; then
  echo "[dshhost] --compile-only：跳过链接（不需要 ${NODE_SONAME}）"
  exit 0
fi

if [ ! -f "$LIBNODE" ]; then
  echo "[dshhost] ✗ 找不到 ${NODE_SONAME}（${LIBNODE_DIR}/）——先跑完 build-node-ohos.sh" >&2
  echo "[dshhost]   提示：Node 输出必须提供 ${NODE_SONAME}，脚本不再依赖通用 libnode.so symlink" >&2
  exit 1
fi

# Verify the Node binary advertises the same SONAME that dshhost will require.
NODE_SONAME_ACTUAL="$($READELF -d "$LIBNODE" 2>/dev/null | sed -n 's/.*SONAME.*\[\([^]]*\)\].*/\1/p' | head -n 1)"
if [ "$NODE_SONAME_ACTUAL" != "$NODE_SONAME" ]; then
  echo "[dshhost] ✗ Node SONAME 不匹配：期望 ${NODE_SONAME}，实际 ${NODE_SONAME_ACTUAL:-<none>}" >&2
  exit 1
fi

aarch64_check="$($READELF -h "$LIBNODE" 2>/dev/null | grep -E 'Class:|Machine:' || true)"
echo "--- Node runtime (${NODE_SONAME}) ---"
echo "$aarch64_check"
echo "SONAME: ${NODE_SONAME_ACTUAL}"

mkdir -p "$OUT_DIR"
echo "[dshhost] linking → ${OUT_SO#${REPO}/}"
if ! "$CXX_OHOS" "${CFLAGS[@]}" -shared -o "$OUT_SO" /tmp/dshhost.o \
      -L"${LIBNODE_DIR}" -Wl,-l:libnode.so.127 -lhilog_ndk.z -Wl,-soname,libdshhost.so; then
  echo "[dshhost] ✗ 链接失败" >&2
  exit 1
fi

echo "[dshhost] ✓ ${OUT_SO}"
"$READELF" -h "$OUT_SO" | grep -E 'Class|Machine|Type' || true
echo "--- 需要的动态库（必须包含 ${NODE_SONAME}，且随 HAP 一起打包）---"
"$READELF" -d "$OUT_SO" | grep NEEDED || true
echo "--- Node NEEDED 校验 ---"
if "$READELF" -d "$OUT_SO" | grep -Fq "Shared library: [${NODE_SONAME}]"; then
  echo "    ✓ NEEDED = ${NODE_SONAME}"
else
  echo "    ✗ NEEDED 未包含 ${NODE_SONAME}" >&2
  exit 1
fi
echo "--- 签名段（应出现 .codesign；没有就要补签，见 D6 §4.2 R4）---"
"$READELF" -S "$OUT_SO" | grep -E '\.codesign' || echo "    （未检出 .codesign）"
