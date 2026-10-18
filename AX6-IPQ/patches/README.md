# miniupnpd 补丁（AX6 精简固件专用）

## 为什么要自己写补丁

上游 `immortalwrt/packages` 的 `net/miniupnpd/patches/` 里有 5 个补丁：

| 补丁 | 大小 | 在 2.3.11 上的状态 |
|---|---|---|
| `010-upnp-igdv2-compat.patch` | 3,438 B | 能打上（靠 offset 4/66/84） |
| `020-descr-filter-fix.patch` | 10,411 B | **FAILED**（5/7 + 2/2 hunks） |
| `030-allow-private-fix.patch` | 809 B | **FAILED**（1/1 hunk） |
| `040-improve-logging.patch` | 16,352 B | 未验证，大概率 FAILED |
| `900-miniupnpd-format-xml-to-make-some-app-happy.patch` | 19,591 B | 未验证，大概率 FAILED |

`patch` 遇到任何一个 hunk 失败就把**整包**标记为 failed，即使前面的 hunk 已经打上了。
所以只要 `020` 失败，`900` 里那 6 行真正有用的 `upnpdescgen.c` 改动也一起作废。

## 本目录的两个补丁

### `900-ax6-xml-format-desc.patch`（核心，必装）

从上游 900 补丁里**只提取 `upnpdescgen.c` 的 3 个 hunk**，共 6 行插入。

作用：在 `genXML()` 里给每个 XML 元素闭合的 `>` 后插入 `\r\n`，让所有设备描述文件
（`rootDesc.xml`、`WANIPCn.xml`、`WANCfg.xml`、`L3F.xml`、`6FC.xml`、`DP.xml`）
变成带换行的可读格式。

**这是游戏主机（PS4/PS5/Xbox）能发现路由器的关键** —— 它们的 UPnP 客户端解析器
是严格实现，某些版本无法解析整行压缩的 XML。

### `901-ax6-xml-format-soap.patch`（可选）

从 900 的 `upnpsoap.c` 部分挑出游戏主机最常用的 4 个 SOAP 响应函数：
`GetExternalIPAddress`、`AddPortMapping`、`GetSpecificPortMappingEntry`、`DeletePortMapping`。
涉及 `upnpsoap.c` 的改动在 2.3.11 上可能撞车，需本地验证后决定是否启用。

## 怎么用

`diy.sh` 的 `[step] miniupnpd 补丁兼容性处理` 会：

1. 清空上游 `patches/` 目录里所有补丁；
2. 把本目录下 `*.patch` 复制进去；
3. 硬断言：`patches/` 里恰好只有这两个文件。

`KEEP_PATCHES` 变量控制白名单；本目录里的文件会自动加入白名单。

## 怎么验证

见 `AX6-交接文档.md` 第 6.4 节。核心命令：

```sh
git clone --depth=1 -b miniupnpd_2_3_11 https://github.com/miniupnp/miniupnp /tmp/miniupnp
cd /tmp/miniupnp
patch -p1 --dry-run < <本项目>/AX6-IPQ/patches/900-ax6-xml-format-desc.patch
```

期望输出 `checking file miniupnpd/upnpdescgen.c`，无任何 FAILED。
