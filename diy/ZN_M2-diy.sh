#!/bin/bash
# ZN_M2 diy 脚本 —— 修复版 v2
# 源码：LiBwrt/LibWrt 分支 25.12-nss（原 main-nss 分支已废弃）
# 目标插件：OpenClash + ZeroTier + TTYD
#
# v2 修复要点：
#   1. 三处 sed 加容错（LiBwrt 下 lean/autocore 等路径不存在）
#   2. Clash Meta arm64 内核下载加 3 次重试
#   3. 新源码的 feeds 不含 OpenClash，此处显式拉取
#   4. 显式补全 OpenClash 运行依赖

set -u

# ---- 通用容错 sed：目标文件不存在时静默跳过，不中断编译 ----
safe_sed() {
  local pattern="$1"; shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    sed -i "$pattern" "$f" 2>/dev/null
  done
  return 0
}

echo "=========================================="
echo " ZN M2 diy script (fixed v2)"
echo "=========================================="

# 修改本地时间格式（lean/autocore 在 LiBwrt 中可能不存在，已容错）
safe_sed 's/os.date()/os.date("%Y-%m-%d %H:%M:%S %A")/g' package/lean/autocore/files/*/index.htm

# 修改默认主题
safe_sed 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 调整 zerotier 到「服务」菜单
safe_sed 's/vpn/services/g' feeds/luci/applications/luci-app-zerotier/root/usr/share/luci/menu.d/luci-app-zerotier.json

# ==========================================================
# 拉取 OpenClash
# LiBwrt 25.12-nss 的 feeds.conf.default 只有官方源，不含 OpenClash，
# 必须显式取回，否则 CONFIG_PACKAGE_luci-app-openclash=y 会被静默丢弃。
# ==========================================================
echo ">>> [1/3] 获取 luci-app-openclash"
if [ ! -d "package/luci-app-openclash" ]; then
  OK=0
  for i in 1 2 3; do
    rm -rf /tmp/_oc_tmp
    if git clone --depth 1 --quiet https://github.com/vernesong/OpenClash /tmp/_oc_tmp 2>/dev/null; then
      if [ -d "/tmp/_oc_tmp/luci-app-openclash" ]; then
        mv -f /tmp/_oc_tmp/luci-app-openclash package/luci-app-openclash && OK=1 && break
      fi
    fi
    echo "    第 $i 次拉取失败，重试..."
    sleep 5
  done
  rm -rf /tmp/_oc_tmp
  if [ "$OK" = "1" ]; then
    echo "    OpenClash 已就位"
  else
    echo "    [警告] OpenClash 拉取失败"
  fi
else
  echo "    已存在，跳过"
fi

# ==========================================================
# 把 Clash Meta 内核（arm64）打包进固件只读层
# 关键点：内核落在 rootfs(squashfs 59.3 MiB)，不占用仅 27.7 MiB 的 overlay，
# 这才是这台 256MB 小机能跑 OpenClash 的原因。
# ==========================================================
echo ">>> [2/3] 下载 Clash Meta 内核 (arm64)"
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
  echo "    第 $attempt 次下载失败，重试..."
  sleep 5
done

if [ "$CLASH_OK" = "1" ]; then
  if [ -f files/etc/openclash/core/clash ]; then
    mv -f files/etc/openclash/core/clash files/etc/openclash/core/clash_meta
  fi
  chmod +x files/etc/openclash/core/clash_meta 2>/dev/null
  echo "    Meta 内核已就位："
  ls -lh files/etc/openclash/core/ || true
else
  echo "    [警告] Meta 内核下载失败，刷机后可手动上传或在线更新获取"
fi

rm -f "clash_meta.tar.gz"

# ==========================================================
# 刷新 feeds
# ==========================================================
echo ">>> [3/3] 更新 feeds"
./scripts/feeds update -a
./scripts/feeds install -a

echo "=========================================="
echo " diy 脚本执行完毕"
echo "=========================================="
exit 0
