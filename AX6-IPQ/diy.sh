#!/bin/bash
# ============================================================================
# AX6 精简固件 —— 编译期定制脚本
# 放置位置：AX6-IPQ/diy.sh（与 .config、apply-config.sh 同级）
# 调用位置：workflow 的 `Load custom config` 步骤，执行 `cd openwrt` 之后调用，
#           即在 `./scripts/feeds install -a` 之后、`make defconfig` 之前。
#
# 职责：
#   0) 环境自检（打印 pwd、校验在 openwrt 树根，失败立刻中止）
#   1) 规避 miniupnpd 补丁不兼容（放在最前，与 feed 无关先做掉）
#   2) 挂载 nikki 第三方 feed
#   3) 应用精简 .config（幂等翻转符号）
#   4) 固化 DNS 三级串联预设到 rootfs
#
# 设计要点：每一步都打印 [step] 前缀，便于在 Actions 日志里 Ctrl+F 定位；
#          所有对 openwrt 树的操作用绝对路径，不依赖 cd 状态。
# ============================================================================
set -e

DIY_DIR="$(cd "$(dirname "$0")" && pwd)"
CALLER_PWD="$(pwd)"
echo "=================================================================="
echo "==> [diy] diy.sh 开始"
echo "==> [diy] DIY_DIR    = $DIY_DIR"
echo "==> [diy] CALLER_PWD = $CALLER_PWD"
echo "=================================================================="

# ---------------------------------------------------------------------------
# 0) 环境自检：必须在 openwrt 树根（存在 include/toplevel.mk）
#    若不在，尝试自动切到 $CALLER_PWD/openwrt；仍失败就中止，避免"静默跳过"。
# ---------------------------------------------------------------------------
if [ -f include/toplevel.mk ]; then
	TOP="$(pwd)"
elif [ -f "$CALLER_PWD/openwrt/include/toplevel.mk" ]; then
	TOP="$CALLER_PWD/openwrt"
	cd "$TOP"
else
	echo "==> [diy] [致命] 当前目录不是 OpenWrt 源码树：pwd=$(pwd)"
	echo "==> [diy] [致命] 期望存在 include/toplevel.mk"
	exit 1
fi
echo "==> [diy] OPENWRT TOP = $TOP"

# ---------------------------------------------------------------------------
# 1) 规避 miniupnpd 补丁不兼容
#    背景：feeds/packages 于 2026-10-07 06:35 UTC 把 miniupnpd 升到 2.3.11
#          （commit 983e2638），但 patches/020-descr-filter-fix.patch 仍按
#          旧版 upnppermissions.c 的行号编写，导致：
#            5 out of 7 hunks FAILED (upnppermissions.c)
#            2 out of 2 hunks FAILED (upnppermissions.h)
#            Patch failed! -> package/feeds/packages 编译中断
#    处置：移除该补丁。OpenWrt 的 Build/Prepare 只遍历 patches/*.patch，
#          文件不存在即跳过。保留 miniupnpd 2.3.11（含 PinholeVerification
#          堆溢出修复），仅失去 describe 字段过滤这一项加固。
#    注意：make 实际扫描的是 package/feeds/packages/miniupnpd（./scripts/feeds
#          install 建立的软链或副本），必须与 feeds/packages 一起清理。
# ---------------------------------------------------------------------------
echo "==> [diy] [step] miniupnpd 补丁兼容性处理"
BAD_PATCH_NAME="020-descr-filter-fix.patch"
for base in \
	"$TOP/feeds/packages/net/miniupnpd" \
	"$TOP/package/feeds/packages/miniupnpd"
do
	if [ ! -e "$base" ]; then
		echo "==> [diy]   [跳过] $base 不存在"
		continue
	fi
	if [ -L "$base" ]; then
		echo "==> [diy]   $base 是软链 -> $(readlink -f "$base")"
	else
		echo "==> [diy]   $base 是实体目录"
	fi
	# 软链的话，readlink 解析出的真实目录也要处理
	REAL="$(readlink -f "$base" 2>/dev/null || echo "$base")"
	for dir in "$base" "$REAL"; do
		if [ -f "$dir/patches/$BAD_PATCH_NAME" ]; then
			rm -f "$dir/patches/$BAD_PATCH_NAME"
			echo "==> [diy]   已删除 $dir/patches/$BAD_PATCH_NAME"
		fi
		find "$dir" -name '*.rej' -delete 2>/dev/null || true
		find "$dir" -name '*.orig' -delete 2>/dev/null || true
		n=$(ls "$dir"/patches/*.patch 2>/dev/null | wc -l)
		echo "==> [diy]   $dir 剩余补丁：$n 个"
	done
done

# 清掉上一轮失败留下的构建目录/准备标记，确保 make 重新解包
rm -rf "$TOP"/build_dir/target-*/miniupnpd-* 2>/dev/null || true
echo "==> [diy]   已清理 build_dir 中的 miniupnpd-* 残留"

# 硬断言：补丁若仍在，立刻失败（不要等到 3 小时后编译阶段才炸）
STILL="$(find "$TOP/feeds/packages" "$TOP/package/feeds" \
	-name "$BAD_PATCH_NAME" -print 2>/dev/null || true)"
if [ -n "$STILL" ]; then
	echo "==> [diy] [致命] miniupnpd 不兼容补丁仍然存在："
	echo "$STILL"
	exit 1
fi
echo "==> [diy]   miniupnpd 补丁检查通过"

# ---------------------------------------------------------------------------
# 2) 挂载 nikki feed（mihomo 内核 + LuCI 界面）
# ---------------------------------------------------------------------------
echo "==> [diy] [step] 处理 nikki feed"
if [ -f "$TOP/feeds.conf.default" ]; then
	if ! grep -q 'src-git nikki' "$TOP/feeds.conf.default"; then
		echo "==> [diy]   添加 nikki feed"
		echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >>"$TOP/feeds.conf.default"
	fi
	( cd "$TOP" && ./scripts/feeds update nikki ) || true
	( cd "$TOP" && ./scripts/feeds install -a -p nikki ) || {
		echo "==> [diy]   feed 安装失败，回退为直接克隆"
		git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git \
			"$TOP/package/nikki-openwrt" || true
	}
else
	echo "==> [diy]   [警告] 找不到 feeds.conf.default，跳过 nikki feed"
fi

# ---------------------------------------------------------------------------
# 3) 应用精简配置（幂等：翻转符号，不整文件覆盖，保留 make defconfig 的推导结果）
# ---------------------------------------------------------------------------
echo "==> [diy] [step] 应用精简配置"
if [ -f "$DIY_DIR/apply-config.sh" ]; then
	echo "==> [diy]   调用 apply-config.sh"
	( cd "$TOP" && sh "$DIY_DIR/apply-config.sh" .config )
else
	echo "==> [diy]   [警告] 未找到 apply-config.sh，跳过符号调整"
fi

# ---------------------------------------------------------------------------
# 4) 固化 DNS 三级串联预设到 rootfs
#    链路：客户端 -> ADG(:53) -> smartdns(:6053) -> nikki/mihomo(:1053) -> 上游
#    uci-defaults 脚本在首次开机时自动执行一次，执行后自删。
#    同时放一份到 /root，方便随时重跑。
# ---------------------------------------------------------------------------
echo "==> [diy] [step] 安装 DNS 串联预设"
DNS_CHAIN_SRC="$DIY_DIR/dns-chain.uci-defaults"
DNS_CHAIN_DST="$TOP/package/base-files/files/etc/uci-defaults/99-ax6-dns-chain"
DNS_CHAIN_ROOT="$TOP/package/base-files/files/root/dns-chain.sh"

if [ -f "$DNS_CHAIN_SRC" ]; then
	mkdir -p "$(dirname "$DNS_CHAIN_DST")"
	cp -f "$DNS_CHAIN_SRC" "$DNS_CHAIN_DST"
	chmod 0755 "$DNS_CHAIN_DST"
	# 去掉可能的 CRLF，否则 /bin/sh 执行时会报 "not found"
	sed -i 's/\r$//' "$DNS_CHAIN_DST"
	echo "==> [diy]   -> $DNS_CHAIN_DST"

	mkdir -p "$(dirname "$DNS_CHAIN_ROOT")"
	cp -f "$DNS_CHAIN_SRC" "$DNS_CHAIN_ROOT"
	chmod 0755 "$DNS_CHAIN_ROOT"
	sed -i 's/\r$//' "$DNS_CHAIN_ROOT"
	echo "==> [diy]   -> $DNS_CHAIN_ROOT"
else
	echo "==> [diy]   [警告] 未找到 $DNS_CHAIN_SRC，DNS 串联需开机后手工配置"
fi

# ---------------------------------------------------------------------------
# 5) 收尾自检：确认关键改动真的落地了
# ---------------------------------------------------------------------------
echo "==> [diy] [step] 收尾自检"
grep -q '^CONFIG_TARGET_qualcommax_ipq807x_DEVICE_redmi_ax6-stock=y$' "$TOP/.config" \
	&& echo "==> [diy]   profile 符号 OK" \
	|| echo "==> [diy]   [警告] .config 里没有 redmi_ax6-stock 的 profile 符号"
echo "==> [diy]   .config 行数：$(wc -l < "$TOP/.config")"
echo "==> [diy]   已启用的 luci-app 数量：$(grep -c '^CONFIG_PACKAGE_luci-app-[a-z0-9-]*=y$' "$TOP/.config" || echo 0)"
echo "=================================================================="
echo "==> [diy] diy.sh 全部完成"
touch /tmp/diy-ok
echo "=================================================================="
