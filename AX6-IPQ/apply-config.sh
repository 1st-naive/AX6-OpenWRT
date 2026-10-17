#!/bin/sh
# ============================================================================
# AX6 精简固件配置纠正脚本（幂等）——  只保留：
#   smartdns / turboacc(等价开关) / upnp / ZeroTier / nikki / ADGuardHome
# 用法（在 openwrt 源码根目录、make defconfig 之前执行）：
#   sh AX6-IPQ/apply-config.sh .config
# 说明：本脚本每次运行都会把「该关的关掉、该开的打开」重新写一遍，
#       所以 .config 被 diy.sh / feeds 改动过也能拉回正确状态。
# ============================================================================
set -e
CFG="${1:-.config}"
[ -f "$CFG" ] || { echo "ERROR: $CFG 不存在（请在源码根目录运行）" >&2; exit 1; }

# set_sym <符号> <y|n>：把符号写成 y 或 "# ... is not set"，并去重
set_sym() {
	sym="$1"; val="$2"
	case "$val" in
	y)
		sed -i "/^# ${sym} is not set$/d" "$CFG"
		sed -i "/^${sym}=/d" "$CFG"
		printf '%s=y\n' "$sym" >>"$CFG"
		;;
	n)
		sed -i "/^${sym}=/d" "$CFG"
		grep -q "^# ${sym} is not set$" "$CFG" || printf '# %s is not set\n' "$sym" >>"$CFG"
		;;
	esac
}

echo "==> [1/4] 关闭不属于本次精简清单的插件"
# 不在此列表的即保留。保留项 = smartdns / turboacc(等价开关) / upnp / ZeroTier / nikki / ADGuardHome
#   + 用户指定加回：AutoReboot / Chrony / FullCone NAT / SQM / Natmap / RAMFree
for s in \
	CONFIG_PACKAGE_luci-app-easytier CONFIG_PACKAGE_easytier CONFIG_PACKAGE_easytier-noweb \
	CONFIG_PACKAGE_luci-app-socat \
	CONFIG_PACKAGE_luci-app-ddns-go CONFIG_PACKAGE_ddns-go \
	CONFIG_PACKAGE_luci-app-vlmcsd CONFIG_PACKAGE_vlmcsd \
	CONFIG_PACKAGE_luci-app-watchcat CONFIG_PACKAGE_watchcat \
	CONFIG_PACKAGE_luci-app-diskman \
	CONFIG_PACKAGE_luci-app-timewol \
	CONFIG_PACKAGE_luci-app-wol CONFIG_PACKAGE_etherwake \
	CONFIG_PACKAGE_luci-app-argon-config \
	CONFIG_PACKAGE_luci-i18n-easytier-zh-cn CONFIG_PACKAGE_luci-i18n-socat-zh-cn \
	CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn \
	CONFIG_PACKAGE_luci-i18n-watchcat-zh-cn \
	CONFIG_PACKAGE_luci-i18n-diskman-zh-cn \
	CONFIG_PACKAGE_luci-i18n-timewol-zh-cn \
	CONFIG_PACKAGE_luci-i18n-wol-zh-cn \
	CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn
do
	set_sym "$s" n
done

echo "==> [2/4] 保留 PassWall 全家 / ISC-DHCP 关闭（沿用既有结论，避免和 dnsmasq 抢 53/546）"
for s in \
	CONFIG_PACKAGE_luci-app-passwall CONFIG_PACKAGE_luci-app-passwall2 \
	CONFIG_PACKAGE_luci-app-ssr-plus CONFIG_PACKAGE_luci-app-openclash \
	CONFIG_PACKAGE_luci-app-homeproxy CONFIG_PACKAGE_luci-app-mosdns \
	CONFIG_PACKAGE_luci-app-alist CONFIG_PACKAGE_luci-app-webdav \
	CONFIG_PACKAGE_luci-app-samba4 CONFIG_PACKAGE_luci-app-ksmbd \
	CONFIG_PACKAGE_luci-app-minidlna CONFIG_PACKAGE_luci-app-gecoosac \
	CONFIG_PACKAGE_isc-dhcp-client-ipv6 CONFIG_PACKAGE_isc-dhcp-relay-ipv6 \
	CONFIG_PACKAGE_isc-dhcp-server-ipv6 CONFIG_PACKAGE_generate-ipv6-address
do
	set_sym "$s" n
done

echo "==> [3/4] 打开 6 项功能本体 + 用户指定加回的 6 项 + 必要基础设施"
for s in \
	CONFIG_PACKAGE_adguardhome CONFIG_PACKAGE_luci-app-adguardhome \
	CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn \
	CONFIG_PACKAGE_smartdns CONFIG_PACKAGE_luci-app-smartdns CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn \
	CONFIG_PACKAGE_miniupnpd-nftables CONFIG_PACKAGE_luci-app-upnp CONFIG_PACKAGE_luci-i18n-upnp-zh-cn \
	CONFIG_PACKAGE_zerotier CONFIG_PACKAGE_luci-app-zerotier CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn \
	CONFIG_PACKAGE_nikki CONFIG_PACKAGE_mihomo-meta CONFIG_PACKAGE_luci-app-nikki CONFIG_PACKAGE_luci-i18n-nikki-zh-cn \
	CONFIG_PACKAGE_kmod-tcp-bbr CONFIG_PACKAGE_kmod-nft-offload CONFIG_PACKAGE_kmod-tun \
	CONFIG_PACKAGE_chrony CONFIG_PACKAGE_luci-app-chrony CONFIG_PACKAGE_luci-i18n-chrony-zh-cn \
	CONFIG_PACKAGE_fullconenat-sonic CONFIG_PACKAGE_luci-app-fullconenat-sonic CONFIG_PACKAGE_luci-i18n-fullconenat-sonic-zh-cn \
	CONFIG_PACKAGE_sqm-scripts CONFIG_PACKAGE_luci-app-sqm CONFIG_PACKAGE_luci-i18n-sqm-zh-cn \
	CONFIG_PACKAGE_natmap CONFIG_PACKAGE_luci-app-natmap CONFIG_PACKAGE_luci-i18n-natmap-zh-cn \
	CONFIG_PACKAGE_luci-app-autoreboot CONFIG_PACKAGE_luci-i18n-autoreboot-zh-cn \
	CONFIG_PACKAGE_luci-app-ramfree CONFIG_PACKAGE_luci-i18n-ramfree-zh-cn \
	CONFIG_PACKAGE_luci-app-firewall CONFIG_PACKAGE_luci-i18n-firewall-zh-cn \
	CONFIG_PACKAGE_luci-app-uhttpd CONFIG_PACKAGE_luci-i18n-uhttpd-zh-cn \
	CONFIG_PACKAGE_luci-app-package-manager CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn \
	CONFIG_PACKAGE_luci-i18n-base-zh-cn CONFIG_PACKAGE_luci-theme-argon CONFIG_PACKAGE_luci-theme-bootstrap
do
	set_sym "$s" y
done

echo "==> [4/4] 自检：本清单之外不应再有 luci-app 处于开启状态"
grep '^CONFIG_PACKAGE_luci-app-[a-z0-9-]*=y$' "$CFG" | while read -r line; do
	case "$line" in
		*luci-app-adguardhome=y|*luci-app-firewall=y|*luci-app-nikki=y|*luci-app-package-manager=y|\
		*luci-app-smartdns=y|*luci-app-uhttpd=y|*luci-app-upnp=y|*luci-app-zerotier=y|\
		*luci-app-autoreboot=y|*luci-app-chrony=y|*luci-app-fullconenat-sonic=y|\
		*luci-app-sqm=y|*luci-app-natmap=y|*luci-app-ramfree=y) ;;
		*) bad=1; echo "  [警告] 仍处于开启状态：$line" ;;
	esac
done

echo "==> [5/5] 兜底：确保被精简插件依赖的符号也已显式关闭"
# 这些符号在原 .config 里可能从未出现（靠 depends 被动选中），
# 必须显式写成 "# ... is not set"，否则 make defconfig 会顺着依赖把它们重新选回来。
# 注意：sqm-scripts / natmap / chrony / fullconenat-sonic 已按用户要求保留，不在此处关闭。
for s in \
	CONFIG_PACKAGE_easytier CONFIG_PACKAGE_easytier-noweb \
	CONFIG_PACKAGE_frp CONFIG_PACKAGE_frpc CONFIG_PACKAGE_luci-app-frpc
do
	set_sym "$s" n
done

echo "==> apply-config.sh 完成（turboacc 本体不在 ImmortalWrt 树内，用 kmod-tcp-bbr + kmod-nft-offload 等价实现）"
# 注意：bad=1 只是提示，不终止构建；构建日志里搜 "[警告]" 即可确认。
exit 0
