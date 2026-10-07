#!/bin/sh
# apply-config.sh —— 把 OpenWrt 的 .config 纠正成「AX6 重构版」（幂等，可反复执行）
#
# 用法：cd openwrt && sh /path/to/apply-config.sh [.config]
# 时机：必须在 make defconfig 之前执行（diy.sh 末尾已自动调用）。
# 作用：关掉 PassWall 全家 / ISC-DHCP(IPv6) / 网络共享 / GecoosAC，
#       打开 nikki + 等价加速开关（BBR），并确保 UPnP、ZeroTier、smartdns、IPv6 不被误关。

CFG="${1:-.config}"
[ -f "$CFG" ] || { echo "apply-config.sh: 找不到 $CFG" >&2; exit 1; }

set_sym() { # $1=符号(带 CONFIG_ 前缀)  $2=y|n
	sym="$1"; val="$2"
	case "$val" in
	y)
		sed -i "/^# ${sym} is not set$/d" "$CFG"
		sed -i "/^${sym}=/d" "$CFG"
		printf '%s=y\n' "$sym" >> "$CFG"
		;;
	n)
		sed -i "/^${sym}=/d" "$CFG"
		grep -q "^# ${sym} is not set$" "$CFG" || printf '# %s is not set\n' "$sym" >> "$CFG"
		;;
	esac
}

# ---------- 关闭：PassWall 全家 ----------
for s in \
	luci-app-passwall \
	luci-app-passwall_Nftables_Transparent_Proxy \
	luci-app-passwall_Iptables_Transparent_Proxy \
	luci-app-passwall_INCLUDE_Geoview \
	luci-app-passwall_INCLUDE_Haproxy \
	luci-app-passwall_INCLUDE_SingBox \
	luci-app-passwall_INCLUDE_V2ray_Geodata \
	luci-app-passwall_INCLUDE_Xray \
	luci-i18n-passwall-zh-cn \
	xray-core sing-box v2ray-geoip v2ray-geosite geoview \
	chinadns-ng dns2socks microsocks tcping ipt2socks haproxy ; do
	set_sym "CONFIG_PACKAGE_$s" n
done

# ---------- 关闭：ISC DHCP(IPv6) 三件套 + generate-ipv6-address ----------
# IPv4 DHCP 交回 dnsmasq-full，IPv6 RA/DHCPv6 交回 odhcpd-ipv6only
for s in isc-dhcp-client-ipv6 isc-dhcp-relay-ipv6 isc-dhcp-server-ipv6 generate-ipv6-address ; do
	set_sym "CONFIG_PACKAGE_$s" n
done

# ---------- 关闭：网络共享 / GecoosAC ----------
for s in \
	luci-app-samba4 samba4-server samba4-libs \
	luci-app-ksmbd ksmbd-server \
	luci-app-minidlna minidlna \
	luci-app-webdav luci-app-alist \
	luci-app-gecoosac ; do
	set_sym "CONFIG_PACKAGE_$s" n
done

# ---------- 打开：nikki（mihomo 内核）+ 等价加速开关 ----------
for s in nikki mihomo-meta luci-app-nikki luci-i18n-nikki-zh-cn kmod-tcp-bbr ; do
	set_sym "CONFIG_PACKAGE_$s" y
done

# ---------- 打开：确保这几个功能不被误关 ----------
for s in \
	luci-app-smartdns smartdns \
	luci-app-upnp miniupnpd-nftables \
	luci-app-zerotier zerotier \
	odhcp6c odhcpd-ipv6only luci-proto-ipv6 \
	kmod-nft-offload kmod-tun ; do
	set_sym "CONFIG_PACKAGE_$s" y
done

echo "== apply-config.sh 完成，抽查 =="
echo "-- 应为 =y --"
grep -nE '^CONFIG_PACKAGE_(nikki|mihomo-meta|luci-app-nikki|luci-i18n-nikki-zh-cn|kmod-tcp-bbr|luci-app-smartdns|luci-app-upnp|luci-app-zerotier|odhcp6c|odhcpd-ipv6only)=' "$CFG" || true
echo "-- 应为空（残留检查）--"
if grep -nE '^CONFIG_PACKAGE_(luci-app-passwall|xray-core|sing-box|haproxy|tcping|ipt2socks|microsocks|geoview|chinadns-ng|dns2socks|isc-dhcp|generate-ipv6-address|luci-app-samba4|luci-app-ksmbd|luci-app-gecoosac)=' "$CFG"; then
	echo "!! 上面这些还在，请把它们改成 '# CONFIG_XXX is not set' 后再 make defconfig"
else
	echo "干净"
fi
