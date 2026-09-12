#!/usr/bin/env bash
# 只报告三件事：构建是否还在跑、产物是否出现、日志最后两行的前 120 字符。
# ASCII only；输出刻意极小，避免把整条编译命令行刷进日志。
SRC="${HOME}/ohos/node-v22.23.2"
LOG="${HOME}/ohos/build-node.log"

echo "--- runners ---"
if pgrep -f 'make' > /dev/null 2>&1; then echo "make RUNNING"; else echo "make IDLE"; fi
if pgrep -f 'build-node-ohos' > /dev/null 2>&1; then echo "script RUNNING"; else echo "script IDLE"; fi

echo "--- artifacts ---"
found=0
for f in "${SRC}/out/Release/libnode.so" "${SRC}/out/Release/libnode.so.127" "${SRC}/out/Release/node"; do
  if [ -e "$f" ]; then
    echo "PRESENT $(stat -c%s "$f") $f"
    found=1
  fi
done
if [ "$found" = "0" ]; then
  echo "none"
  echo "so candidates:"; ls -1 "${SRC}/out/Release/" 2>/dev/null | grep -i 'libnode\|^node$' || echo "  (no libnode/node names in out/Release)"
fi

echo "--- log tail (truncated) ---"
tail -n 2 "${LOG}" 2>/dev/null | cut -c1-120
