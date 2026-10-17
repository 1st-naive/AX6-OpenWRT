#!/bin/bash
# ============================================================================
# AX6 精简固件 —— 编译期定制脚本
# 放置位置：AX6-IPQ/diy.sh（与 .config、apply-config.sh 同级）
# 被 workflow 在 `./scripts/feeds install` 之后、`make defconfig` 之前调用。
# 职责：1) 挂载 nikki 第三方 feed  2) 应用精简 .config  3) 固化 DNS 串联预设
# ============================================================================
set -e

DIY_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "==> [diy] DIY_DIR = $DIY_DIR"

# ---------------------------------------------------------------------------
# 0) 通用稀疏克隆函数（部分插件仍需从第三方仓库取 Makefile）
# ---------------------------------------------------------------------------
git_sparse_clone() {
	branch="$1"
	shift
	repourl="$1"
	shift
	if [ -z "$repourl" ]; then
		echo "==> [diy] git_sparse_clone: 缺少仓库地址"
		return 1
	fi
	git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl" /tmp/sparse-clone
	cd /tmp/sparse-clone || return 1
	git sparse-checkout init --no-cone
	git sparse-checkout set "$@"
	mv -f "$@" "$DIY_DIR/../package/" 2>/dev/null || true
	cd "$DIY_DIR" || return 1
	rm -rf /tmp/sparse-clone
}

# ---------------------------------------------------------------------------
# 1) 挂载 nikki feed（mihomo 内核 + LuCI 界面）
# ---------------------------------------------------------------------------
if [ -f feeds.conf.default ]; then
	if ! grep -q 'src-git nikki' feeds.conf.default; then
		echo "==> [diy] 添加 nikki feed"
		echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >>feeds.conf.default
	fi
	./scripts/feeds update nikki || true
	./scripts/feeds install -a -p nikki || {
		echo "==> [diy] feeds 安装失败，回退为直接克隆"
		git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki.git package/nikki-openwrt || true
	}
fi

# ---------------------------------------------------------------------------
# 1.5) 规避 miniupnpd 补丁不兼容
#      feeds/packages 于 2026-10-07 把 miniupnpd 升到 2.3.11，但
#      patches/020-descr-filter-fix.patch 仍按旧版行号编写，导致
#      "5 out of 7 hunks FAILED" / "2 out of 2 hunks FAILED" 编译中断。
#      上游尚未修复，这里移除该补丁（仅失去 describe 字段过滤修复，
#      保留 2.3.11 的 PinholeVerification 堆溢出修复）。
#      OpenWrt 的 Build/Prepare 只遍历 patches/*.patch，文件移除即跳过。
# ---------------------------------------------------------------------------
MINIUPNPD_PATCHES="feeds/packages/net/miniupnpd/patches"
if [ -d "$MINIUPNPD_PATCHES" ]; then
	echo "==> [diy] 处理 miniupnpd 补丁兼容性"
	for p in 020-descr-filter-fix.patch; do
		if [ -f "$MINIUPNPD_PATCHES/$p" ]; then
			echo "==> [diy]   移除不兼容补丁 $p"
			rm -f "$MINIUPNPD_PATCHES/$p"
		fi
	done
	# 顺手清掉上一轮失败留下的 .rej / .orig，避免污染源码树
	find feeds/packages/net/miniupnpd -name '*.rej' -delete 2>/dev/null || true
	find feeds/packages/net/miniupnpd -name '*.orig' -delete 2>/dev/null || true
	echo "==> [diy]   剩余补丁：$(ls "$MINIUPNPD_PATCHES"/*.patch 2>/dev/null | wc -l) 个"
fi

# ---------------------------------------------------------------------------
# 2) 应用精简配置（幂等：翻转符号，不整文件覆盖，保留 make defconfig 的推导结果）
# ---------------------------------------------------------------------------
if [ -f "$DIY_DIR/apply-config.sh" ]; then
	echo "==> [diy] 应用精简配置 apply-config.sh"
	sh "$DIY_DIR/apply-config.sh" .config
else
	echo "==> [diy] [警告] 未找到 apply-config.sh，跳过符号调整"
fi

# ---------------------------------------------------------------------------
# 3) 固化 DNS 三级串联预设到 rootfs
#    链路：客户端 → ADG(:53) → smartdns(:6053) → nikki/mihomo(:1053) → 上游
#    uci-defaults 脚本在首次开机时自动执行一次，执行后自删。
# ---------------------------------------------------------------------------
DNS_CHAIN_SRC="$DIY_DIR/dns-chain.uci-defaults"
DNS_CHAIN_DST="package/base-files/files/etc/uci-defaults/99-ax6-dns-chain"

if [ -f "$DNS_CHAIN_SRC" ]; then
	echo "==> [diy] 安装 DNS 串联预设 → $DNS_CHAIN_DST"
	mkdir -p "$(dirname "$DNS_CHAIN_DST")"
	cp -f "$DNS_CHAIN_SRC" "$DNS_CHAIN_DST"
	chmod 0755 "$DNS_CHAIN_DST"
	# 去掉可能的 CRLF，否则 /bin/sh 执行时会报 "not found"
	sed -i 's/\r$//' "$DNS_CHAIN_DST"
else
	echo "==> [diy] [警告] 未找到 $DNS_CHAIN_SRC，DNS 串联需开机后手工配置"
fi

# ---------------------------------------------------------------------------
# 4) 可选：把 DNS 串联预设同时放进 /root，方便随时重跑
# ---------------------------------------------------------------------------
if [ -f "$DNS_CHAIN_SRC" ]; then
	mkdir -p package/base-files/files/root
	cp -f "$DNS_CHAIN_SRC" package/base-files/files/root/dns-chain.sh
	chmod 0755 package/base-files/files/root/dns-chain.sh
	sed -i 's/\r$//' package/base-files/files/root/dns-chain.sh
fi

echo "==> [diy] 完成"
