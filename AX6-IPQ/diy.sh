#!/bin/bash
# ============================================================================
# AX6 精简固件 —— 编译期定制脚本
# 放置位置：AX6-IPQ/diy.sh（与 .config、apply-config.sh、patches/ 同级）
# 调用位置：workflow 的 `Load custom config` 步骤，执行 `cd openwrt` 之后调用，
#           即在 `./scripts/feeds install -a` 之后、`make defconfig` 之前。
#
# 职责：
#   0) 环境自检（打印 pwd、校验在 openwrt 树根，失败立刻中止）
#   1) miniupnpd 补丁：清空上游 5 个不兼容补丁，换成 patches/ 下自维护的补丁
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
# 1) miniupnpd 补丁：清空上游、换成本项目自维护的补丁
#    背景：feeds/packages 于 2026-10-07 06:35 UTC 把 miniupnpd 升到 2.3.11
#          （commit 983e2638），但上游 patches/ 下的 5 个补丁仍按旧源码行号编写：
#            010-upnp-igdv2-compat.patch   3,438 B → 能打上（offset 4/66/84）
#            020-descr-filter-fix.patch   10,411 B → 5/7 + 2/2 hunk FAILED
#            030-allow-private-fix.patch     809 B → 1/1 hunk FAILED
#            040-improve-logging.patch    16,352 B → 未验证
#            900-...format-xml....patch   19,591 B → 未验证
#          patch 遇到任一 hunk 失败就把整包标记 failed，前面打上的也作废。
#    处置：
#          ① 清空上游 patches/ 目录里所有 *.patch；
#          ② 从 $DIY_DIR/patches/ 复制本项目自维护的补丁进去；
#          ③ 断言 patches/ 里的文件与本项目提供的**完全一致**。
#    自维护补丁说明（见 patches/README.md）：
#          900-ax6-xml-format-desc.patch —— 从上游 900 只提取 upnpdescgen.c 的
#          3 个 hunk（6 行），给 genXML() 每个 XML 元素闭合的 '>' 后插入 \r\n。
#          这是游戏主机（PS4/PS5/Xbox）能发现路由器的关键。该补丁由本地
#          `git diff` 对 miniupnpd_2_3_11 源码生成并 dry-run 验证通过。
#    注意：make 实际扫描的是 package/feeds/packages/miniupnpd（./scripts/feeds
#          install 建立的软链或副本），必须与 feeds/packages 一起处理。
# ---------------------------------------------------------------------------
echo "==> [diy] [step] miniupnpd 补丁处理"

OUR_PATCH_DIR="$DIY_DIR/patches"

# 1.1 收集本项目提供的补丁文件名（作为白名单）
OUR_PATCHES=""
if [ -d "$OUR_PATCH_DIR" ]; then
	for p in "$OUR_PATCH_DIR"/*.patch; do
		[ -e "$p" ] || continue
		OUR_PATCHES="$OUR_PATCHES $(basename "$p")"
	done
fi
OUR_PATCHES="${OUR_PATCHES# }"
if [ -z "$OUR_PATCHES" ]; then
	echo "==> [diy]   [警告] $OUR_PATCH_DIR 里没有 .patch，miniupnpd 将使用官方原版源码"
else
	echo "==> [diy]   本项目补丁：$OUR_PATCHES"
fi

# 1.2 逐个目录：清空上游补丁，放入本项目补丁
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
		if [ ! -d "$dir" ]; then
			continue
		fi
		mkdir -p "$dir/patches"

		# 清空上游补丁
		for p in "$dir"/patches/*.patch; do
			[ -e "$p" ] || continue
			echo "==> [diy]   [移除上游] $(basename "$p")"
			rm -f "$p"
		done
		find "$dir" -name '*.rej' -delete 2>/dev/null || true
		find "$dir" -name '*.orig' -delete 2>/dev/null || true

		# 放入本项目补丁
		if [ -n "$OUR_PATCHES" ]; then
			for name in $OUR_PATCHES; do
				cp -f "$OUR_PATCH_DIR/$name" "$dir/patches/$name"
				echo "==> [diy]   [放入] $dir/patches/$name"
			done
		fi
	done
done

# 1.3 清掉上一轮失败留下的构建目录/准备标记，确保 make 重新解包
rm -rf "$TOP"/build_dir/target-*/miniupnpd-* 2>/dev/null || true
echo "==> [diy]   已清理 build_dir 中的 miniupnpd-* 残留"

# 1.4 硬断言：patches/ 里的文件必须与本项目提供的一致
#     （不要等到 40 分钟后编译阶段才炸）
BAD=""
for d in "$TOP/feeds/packages/net/miniupnpd" "$TOP/package/feeds/packages/miniupnpd"; do
	[ -d "$d/patches" ] || continue
	for p in "$d"/patches/*.patch; do
		[ -e "$p" ] || continue
		name="$(basename "$p")"
		case " $OUR_PATCHES " in
			*" $name "*) ;;
			*) BAD="$BAD $p" ;;
		esac
	done
	# 反向：本项目提供的每个补丁都必须存在
	for name in $OUR_PATCHES; do
		if [ ! -f "$d/patches/$name" ]; then
			BAD="$BAD 缺少:$d/patches/$name"
		fi
	done
done
if [ -n "$BAD" ]; then
	echo "==> [diy] [致命] miniupnpd patches/ 内容与本项目提供的不一致："
	echo "$BAD"
	exit 1
fi
echo "==> [diy]   miniupnpd 补丁检查通过（实际应用：${OUR_PATCHES:-无}）"

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
