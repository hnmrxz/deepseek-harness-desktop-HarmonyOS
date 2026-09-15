#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"

# ARM64 Ubuntu 上直接安装/放置的 OpenHarmony SDK
OHOS_ROOT="${OHOS_ROOT:-$HOME/ohos}"
OHOS_SDK="${OHOS_SDK:-$OHOS_ROOT/sdk}"

CLANG_DIR="${OHOS_SDK}/native/llvm/bin"
SYSROOT="${OHOS_SDK}/native/sysroot"

CXX="${CLANG_DIR}/aarch64-unknown-linux-ohos-clang++"

# ARM64 Ubuntu 上的 Node OHOS 源码树
NODE_SRC="${NODE_SRC:-$HOME/ohos/node-v22.23.2}"

SRC_FILE="${REPO}/hostruntime/src/main/cpp/dshhost.cc"
OUT_DIR="${REPO}/entry/libs/arm64-v8a"
OUT_SO="${OUT_DIR}/libdshhost.so"

OBJ="${OUT_DIR}/dshhost.o"

if [[ ! -x "${CXX}" ]]; then
  echo "ERROR: OpenHarmony ARM64 clang not found:"
  echo "  ${CXX}"
  exit 1
fi

for d in \
  "${NODE_SRC}/src" \
  "${NODE_SRC}/deps/v8/include" \
  "${NODE_SRC}/deps/uv/include"
do
  [[ -d "${d}" ]] || {
    echo "ERROR: missing Node include tree: ${d}"
    exit 1
  }
done

mkdir -p "${OUT_DIR}"

INCLUDES=(
  "-I${NODE_SRC}/src"
  "-I${NODE_SRC}/deps/v8/include"
  "-I${NODE_SRC}/deps/uv/include"
)

CFLAGS=(
  "--target=aarch64-linux-ohos"
  "--sysroot=${SYSROOT}"
  "-D__MUSL__"
  "-fno-emulated-tls"
  "-std=gnu++20"
  "-fPIC"
  "-O2"
  "-Wall"
  "-Wno-unused-parameter"
)

echo "[dshhost] host: $(uname -m)"
echo "[dshhost] target: OpenHarmony aarch64"
echo "[dshhost] compiler: ${CXX}"
echo "[dshhost] node source: ${NODE_SRC}"

echo "[dshhost] compile..."
"${CXX}" \
  "${CFLAGS[@]}" \
  "${INCLUDES[@]}" \
  -c "${SRC_FILE}" \
  -o "${OBJ}"

echo "[dshhost] compile OK"

LIBNODE="${NODE_SRC}/out/Release/libnode.so"

if [[ ! -e "${LIBNODE}" && ! -e "${LIBNODE}.127" ]]; then
  echo "ERROR: missing OHOS libnode:"
  echo "  ${LIBNODE}"
  echo "Build Node for OpenHarmony first."
  exit 1
fi

echo "[dshhost] link..."

"${CXX}" \
  "${CFLAGS[@]}" \
  -shared \
  -o "${OUT_SO}" \
  "${OBJ}" \
  -L"${NODE_SRC}/out/Release" \
  -lhilog_ndk.z \
  -Wl,-soname,libdshhost.so

echo "[dshhost] output:"
echo "  ${OUT_SO}"

READELF="${CLANG_DIR}/llvm-readelf"

echo
echo "=== ELF ==="
"${READELF}" -h "${OUT_SO}" |
  grep -E 'Class|Machine|Type'

echo
echo "=== NEEDED ==="
"${READELF}" -d "${OUT_SO}" |
  grep NEEDED || true

echo
echo "=== SIGNATURE ==="
"${READELF}" -S "${OUT_SO}" |
  grep -E '\.codesign' || true
