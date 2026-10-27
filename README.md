# luci-app-guard

OpenWrt / ImmortalWrt 上的**外部访问监控**插件：采样 conntrack，只记录真正暴露在公网的服务端口（lucky / 端口转发）和 UPnP 映射，用来判断是否有外部设备访问过这些入口。**只记录，不封禁**，不改任何防火墙规则。

## 设计口径

- 只记 `L`（公网服务/端口转发）和 `U`（UPnP 映射），这两类才是真实外部暴露面。
- 不记 `P`：被 fw4 `reject_from_wan` 拒绝的盲扫没有威胁，而且 5 秒轮询也抓不到短命条目。
- 不记 `B`：无端口映射、落到内机的 P2P/fullcone 回连占原数据 98% 以上，无法用于判断渗透。
- 24h 明细致 `/tmp`（tmpfs），不写闪存；日汇总只保留 `L/U`，旧版约 13–18 MB/天，现降到 < 0.5 MB/天。

## 功能

- **暴露面采集**：lucky `*_auto` 链、`dstnat_wan` 的 `dnat ip to`、`config rule` 里 `src=wan` 的手动放行、UPnP 租约，统一生成 `协议|外部端口 -> 内网落点|内网端口` 映射。
- **只记真实落点**：同号端口落到别的内机时不会误判成公网服务；未回复的转发连接按映射目标归属。
- **四个视图**：来源 IP（归属地/主要落点/公网命中数）、暴露面（L + UPnP 端口清单，含 24h 无流量端口）、告警事件、最近连接。
- **两类告警**（阈值可配）：60 秒内 ≥N 个暴露端口 = 端口扫描；≥M 次连接公网服务 = 高频。只统计 `L`，P2P 不会触发。
- **归属地**：ip-api.com 批量查询，只查 `L/U` 来源前 120 + 告警来源，缓存 7 天，中文显示，可关。
- 三级时间范围：24 小时（内存明细）、7 天、30 天（每日汇总落盘）。
- LuCI 原生视图（不用 iframe），固定行高/表格高度，页签切换不跳动。
- 常驻内存约 1.2–1.5 MB，纯 ash + awk，无额外依赖。

## 安装

```sh
# 方式一：复制本目录到路由器后执行
scp -r luci-app-guard root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sh /tmp/luci-app-guard/install.sh'

# 方式二：OpenWrt SDK 编译
# 将本目录放入 package/ 后 make menuconfig（LuCI → Applications → luci-app-guard）
```

安装后从 LuCI 菜单「服务 → 外部访问监控」进入（`/cgi-bin/luci/admin/services/guard`）。

## 配置

`/etc/config/guard`：

| 选项 | 默认 | 说明 |
|---|---|---|
| `enabled` | 1 | 是否启用 |
| `interval` | 5 | 采样间隔（秒）；10 秒会漏掉 CLOSE 态连接 |
| `scan_ports` | 5 | 60 秒内不同暴露端口数达到多少算扫描 |
| `scan_conns` | 30 | 60 秒内连接公网服务次数达到多少算高频 |
| `retain_days` | 30 | 每日汇总保留天数 |
| `alert_keep` | 5000 | 告警保留条数 |
| `conn_keep` | 50000 | 24h 连接明细条数上限（只含 L/U） |
| `geo` | 1 | 是否查询来源 IP 归属地 |
| `wan_if` | pppoe-wan | WAN 接口名；用于识别本机 WAN 地址 |

改完执行 `/etc/init.d/guard restart` 生效。

**忽略名单**：`/etc/guard/ignore.list`，一行一个端口（`#` 注释），命中的端口直接不记；重启后生效。

## 分类口径

| 分类 | 含义 | 是否记录 |
|---|---|---|
| `L` | 公网服务/端口转发：lucky accept、`dstnat_wan` 的 dnat、`src=wan` 手动规则；落点为路由器或映射的内机 | 记录 |
| `U` | UPnP 映射端口（内机应用主动开放） | 记录 |
| `B` | 无映射、落到内机的 P2P/fullcone 回连 | 不记 |
| `P` | 未落到内机的探测/被拒绝流量 | 不记 |
| `N` | `ignore.list` 命中 | 不记 |

## 数据与留存

| 内容 | 位置 | 留存 |
|---|---|---|
| 连接明细 / 来源 / 暴露面清单（24h） | `/tmp/guard/` | 内存，重启清零 |
| 每日汇总（只含 L/U，含主要落点/落点连接数） | `/etc/guard/daily/YYYY-MM-DD.tsv` | `retain_days` 天 |
| 告警记录（单文件） | `/etc/guard/alerts.tsv` | `alert_keep` 条 |
| 归属地缓存 | `/tmp/guard/geo.tsv` | 7 天 |

每日汇总每小时刷新一次，跨天时定稿；重启后自动读取当天已有汇总作为基线继续累计。明细达到 `conn_keep` 上限时页面显示「已封顶」，并给出实际覆盖时长。24h 无 `L/U` 流量时，覆盖时长按采集启动时间计算，最多显示 24h。

## 资源与闪存

- 24h 明细只存 `L/U`，通常几百条到几千条；`/tmp` 为 tmpfs，不写 eMMC。
- 日汇总每小时写一次，每天约 10–30 KB；告警只在新增时追加并裁剪。
- 旧版每分钟重写 `alerts.tsv`/`alerts.log` 的行为已移除；按 30 天估算总写入 < 0.5 MB/天。

## 接口

```
/cgi-bin/guard?view=summary
/cgi-bin/guard?view=sources&range=24h|7d|30d&page=1&size=15&proto=tcp|all&only=watch|all
/cgi-bin/guard?view=ports&page=1&size=15&proto=tcp|all&only=watch|all
/cgi-bin/guard?view=alerts&range=24h|7d|30d&page=1&size=15&only=watch|all
/cgi-bin/guard?view=events&page=1&size=15&proto=tcp|all&only=watch|all
```

## 卸载

```sh
/etc/init.d/guard stop
/etc/init.d/guard disable
rm -f /etc/init.d/guard /etc/guard/guard.sh /www/cgi-bin/guard \
      /usr/lib/guard/class.awk /www/luci-static/resources/view/guard/overview.js \
      /usr/share/luci/menu.d/luci-app-guard.json
rm -rf /etc/guard /usr/lib/guard
```

## 说明

- 只读取 `/proc/net/nf_conntrack` 与 nft 链，不修改任何规则。
- 不解析载荷、URL、DNS，不记录源端口；只保留时间、来源 IP、目的端口、协议、落点。
- 归属地查询会把来源公网 IP 发往 ip-api.com，可设 `option geo '0'` 关闭。
- 手动 `config rule` 目前只识别 `src=wan` + 固定 `dest_port`；端口段和 IPv6 仍不支持。
- 刷固件前请备份 `/etc/guard`（不在 sysupgrade 默认保留清单里）。

## License

MIT
