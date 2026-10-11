#!/bin/bash
# ZN_M2 diy 脚本 —— 加固版（原 xysck 版本基础上做容错处理）
# 适用：LiBwrt/openwrt-6.x  main-nss 分支 / qualcommax ipq60xx zn_m2
# 目标插件：OpenClash + ZeroTier + TTYD（config 中已默认启用）

set -u

# ---- 通用容错 sed：文件/通配符不存在时静默跳过，不中断编译 ----
safe_sed() {
  local pattern="$1"; shift
  local matched=0
  for f in "$@"; do
    [ -f "$f" ] || continue
    sed -i "$pattern" "$f" 2>/dev/null && matched=1
  done
  return 0
}

# 修改本地时间格式（lean/autocore 在 LiBwrt 中可能不存在，已容错）
safe_sed 's/os.date()/os.date("%Y-%m-%d %H:%M:%S %A")/g' package/lean/autocore/files/*/index.htm

# 修改默认主题
safe_sed 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 调整 zerotier 到「服务」菜单
safe_sed 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/root/usr/share/luci/menu.d/luci-app-zerotier.json

# ==========================================================
# 关键：把 OpenClash Meta 内核（arm64）打包进固件只读层
# 这样内核位于 rootfs(squashfs)，不占用仅 27.7 MiB 的 overlay
# ==========================================================
echo ">>> 下载 Clash Meta 内核 (arm64)"
mkdir -p files/etc/openclash/core

CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
CLASH_OK=0

for attempt in 1 2 3; do
  if wget -qO "clash_meta.tar.gz" "$CLASH_META_URL"; then
    if tar -zxvf "clash_meta.tar.gz" -C files/etc/openclash/core/ >/dev/null 2>&1; then
      CLASH_OK=1
      break
    fi
  fi
  echo ">>> 第 $attempt 次下载失败，重试..."
  sleep 5
done

if [ "$CLASH_OK" = "1" ]; then
  if [ -f files/etc/openclash/core/clash ]; then
    mv -f files/etc/openclash/core/clash files/etc/openclash/core/clash_meta
  fi
  chmod +x files/etc/openclash/core/clash_meta 2>/dev/null
  echo ">>> Clash Meta 内核已就位："
  ls -lh files/etc/openclash/core/ || true
else
  echo ">>> 警告：Meta 内核下载失败，编译时请确认 OpenClash 可在线或手动上传内核"
fi

rm -f "clash_meta.tar.gz"

./scripts/feeds update -a
./scripts/feeds install -a

echo ">>> diy 脚本执行完毕"
exit 0
