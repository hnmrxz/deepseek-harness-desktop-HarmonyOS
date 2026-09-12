#!/usr/bin/env bash
# The ONE definition of the OHOS cross toolchain environment. Source it, do not copy it.
#
# Why this file exists (measured, and it cost a full rebuild to learn):
#   out/Makefile has `CC.target ?= $(CC)` -- gyp's generated makefiles take the TARGET
#   compiler from the environment. Export CC/CXX before `make`, or make silently falls
#   back to the host `cc`/`g++` and compiles *target* objects as x86-64. Nothing fails
#   at compile time; you only find out from a later confusing error (e.g. host gcc
#   hitting `asm/hwcap.h: No such file or directory` while compiling deps/zlib for OHOS).
#   An earlier resume script omitted these exports and polluted 1112 of 2410 target
#   objects with host-compiled ones. Keep the export here, shared by every entry point.
#
# Usage:  source "$(dirname "$0")/toolchain-env.sh"
# ASCII only.

OHOS_ROOT="${OHOS_ROOT:-$HOME/ohos}"
OHOS_SDK="${OHOS_SDK:-$OHOS_ROOT/sdk}"
export OHOS_CLANG_DIR="${OHOS_SDK}/native/llvm/bin"
export OHOS_SYSROOT="${OHOS_SDK}/native/sysroot"

# -fno-emulated-tls: required by the OHOS toolchain ABI (from the Node OHOS port CI usage)
export CC="${OHOS_CLANG_DIR}/aarch64-unknown-linux-ohos-clang -fno-emulated-tls"
export CXX="${OHOS_CLANG_DIR}/aarch64-unknown-linux-ohos-clang++ -fno-emulated-tls"

# Host tools stay host tools (used for obj.host/*)
export CC_host="gcc"
export CXX_host="g++"
export AR_host="ar"

export LD="${OHOS_CLANG_DIR}/ld.lld"
export LDFLAGS="-fuse-ld=lld"

# Guard: refuse to run if the toolchain is not actually there. A missing clang plus a
# silently-host-compiled tree is exactly the failure this file is meant to prevent.
if [ ! -x "${OHOS_CLANG_DIR}/aarch64-unknown-linux-ohos-clang" ]; then
  echo "ERROR: OHOS cross clang not found at ${OHOS_CLANG_DIR}" >&2
  echo "       run tools/node-runtime/fetch-ohos-sdk.sh first" >&2
  return 1 2>/dev/null || exit 1
fi
