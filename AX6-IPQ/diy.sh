#!/bin/bash
# Git稀疏克隆，只克隆指定目录到本地
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
  cd "$repodir" || exit 1
  # --no-cone 才能同时稀疏检出目录和单文件（如 easytier 的 version.mk）
  git sparse-checkout init --no-cone
  git sparse-checkout set "$@"
  mv -f "$@" ../package/
  cd .. && rm -rf "$repodir"
}

# Add packages
# EasyTier 组网（稀疏克隆，menuconfig 里自选 easytier / easytier-noweb）
git_sparse_clone main https://github.com/fightroad/luci-app-easytier easytier easytier-noweb luci-app-easytier version.mk

# Socat 端口转发 LuCI（Lienol 版，兼容新版 socat，配置用 luci_socat 不冲突）
git_sparse_clone main https://github.com/Lienol/openwrt-package luci-app-socat

# nikki（透明代理，mihomo 内核）：官方要求以 feed 方式接入，必须在 feeds install 之后补做
# 注意：workflow 里 feeds update/install 在本脚本之前执行，所以这里要自己补一次
if ! grep -q 'src-git nikki' feeds.conf.default; then
  echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default
fi
./scripts/feeds update nikki
./scripts/feeds install -a -p nikki || {
  echo "feeds install 失败，回退为直接克隆到 package/" >&2
  git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git package/nikki-openwrt
}
# 说明：本 feed 含 nikki / luci-app-nikki / mihomo-meta(默认核心, PROVIDES mihomo) / mihomo-alpha
# mihomo 是 Go 程序，首次编译会连带编 Go host 工具链，约多 10-20 分钟

# frp：用官方预编译包替换 Imm 源码编译（避免 node/host 编 WebUI 失败）
# 保留 feeds 里 Imm 的 files/（init、uci），LuCI 仍用官方 luci-app-frpc
DIY_DIR="$(cd "$(dirname "$0")" && pwd)"
FRP_SRC_MK="$DIY_DIR/frp/Makefile"
FRP_DST_DIR="feeds/packages/net/frp"
if [ ! -f "$FRP_SRC_MK" ]; then
  echo "ERROR: missing $FRP_SRC_MK" >&2
  exit 1
fi
if [ ! -d "$FRP_DST_DIR" ]; then
  echo "ERROR: missing $FRP_DST_DIR (run feeds install first)" >&2
  exit 1
fi
cp -f "$FRP_SRC_MK" "$FRP_DST_DIR/Makefile"
echo "frp: using official prebuilt binary Makefile ($(grep '^PKG_VERSION:=' "$FRP_DST_DIR/Makefile"))"

# frpc：LuCI 启用开关 + 默认关闭（避免未配置时连 127.0.0.1:7000 反复重启）
chmod +x "$DIY_DIR/frp/patch_enable.sh"
"$DIY_DIR/frp/patch_enable.sh" \
  "feeds/packages/net/frp/files" \
  "feeds/luci/applications/luci-app-frpc/htdocs/luci-static/resources/view/frpc.js"

# ============================================================================
# 配置纠正（幂等）：关掉 PassWall 全家 / ISC-DHCP(IPv6) / 网络共享 / GecoosAC，
# 打开 nikki + kmod-tcp-bbr，并确保 UPnP / ZeroTier / smartdns / IPv6 不被误关。
# 必须在 make defconfig 之前执行 —— workflow 里 defconfig 在下一个步骤，顺序正确。
# 如果不想用脚本，删掉这一段即可（那就靠 AX6-IPQ/.config 里已经改好的内容）。
# ============================================================================
if [ -f "$DIY_DIR/apply-config.sh" ]; then
  sh "$DIY_DIR/apply-config.sh" .config
else
  echo "WARNING: 缺少 $DIY_DIR/apply-config.sh，跳过配置纠正" >&2
fi

#git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
#git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config
#git clone --depth 1 https://github.com/sirpdboy/luci-app-ddns-go package/ddnsgo
#git clone --depth 1 https://github.com/sbwml/luci-app-mosdns package/mosdns
#git clone --depth 1 https://github.com/sbwml/luci-app-alist package/alist
#git clone --depth=1  https://github.com/kenzok8/small-package package/small-package
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-zerotier
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages vlmcsd
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-vlmcsd
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-socat

# 替换luci-app-openvpn-server imm源的启动不了服务！
#rm -rf feeds/luci/applications/luci-app-openvpn-server
#git_sparse_clone main https://github.com/kiddin9/kwrt-packages luci-app-openvpn-server
# 调整 openvpn-server 到 VPN 菜单
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/controller/*.lua
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/model/cbi/openvpn-server/*.lua
#sed -i 's/services/vpn/g' package/luci-app-openvpn-server/luasrc/view/openvpn/*.htm

#git clone -b js https://github.com/papagaye744/luci-theme-design package/luci-theme-design

#删除库中的插件，使用自定义源中的包。
#rm -rf feeds/luci/themes/luci-theme-argon
#rm -rf feeds/luci/applications/luci-app-argon-config
#rm -rf feeds/luci/applications/luci-app-ddns-go
#rm -rf feeds/packages/net/ddns-go
#rm -rf feeds/packages/net/alist
#rm -rf feeds/luci/applications/luci-app-alist

#修改默认IP
#sed -i 's/192.168.1.1/192.168.123.1/g' package/base-files/files/bin/config_generate

#修改主机名
#sed -i "s/hostname='ImmortalWrt'/hostname='Redmi-AX6'/g" package/base-files/files/bin/config_generate
