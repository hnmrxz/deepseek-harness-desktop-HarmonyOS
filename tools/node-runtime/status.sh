#!/usr/bin/env bash
# 查看 WSL 侧构建进展（避免在 PowerShell 里嵌套引号）
ROOT="${HOME}/ohos"
echo "=== 相关进程 ==="
pgrep -af '02-build-node|01-fetch-sdk|curl -fL|configure|make -j' | head -10 || echo none
echo
echo "=== SDK 下载/解包 ==="
ls -la "${ROOT}"/*.tar.gz 2>/dev/null || echo "no tarball"
ls -1 "${ROOT}/sdk" 2>/dev/null || echo "sdk 未解出"
echo
echo "=== Node 源码 ==="
ls -d "${HOME}"/node-v* 2>/dev/null || echo "未开始"
echo
echo "=== 构建日志尾部 ==="
tail -n 8 "${ROOT}/build-node.out" 2>/dev/null || echo "尚无"
echo
echo "=== 构建产物 ==="
ls -la "${HOME}"/node-v*/out/Release/libnode.so* "${HOME}"/node-v*/out/Release/node 2>/dev/null || echo "尚未产出"
