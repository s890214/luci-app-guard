# luci-app-guard

OpenWrt / ImmortalWrt 上的**外部访问监控**插件：基于 conntrack 采样，记录所有打到 WAN 的入站连接，按端口归属分类（公网服务 / UPnP / 内机回连 / 未落地），识别扫描与高频，按天汇总保留 30 天。**只记录，不封禁**，不改任何防火墙规则。

## 功能

- **全端口监控**：任何入站连接都记录，不依赖端口清单
- **端口归属**：lucky 公网端口（nft accept + dstnat）、UPnP 租约、无规则内机回连、未落地探测；内网设备名取自 DHCP 租约/静态主机
- **默认只看关注**：只显示公网服务端口命中、扫描告警；P2P/视频回连默认折叠，可切「含正常流量」（自动切全部协议）
- **四个视图**：来源 IP（归属地/主要落点/公网命中数）、暴露面（lucky + UPnP 端口清单，含 24h 无流量端口）、告警事件、最近连接
- **两类告警**（阈值可配）：60 秒内 ≥N 个公网/UPnP 端口 = 端口扫描；≥M 次连接公网端口 = 高频。正常 P2P 高频不再告警
- **归属地**：ip-api.com 批量查询，只查连接数前 120 + 关注/告警来源，缓存 7 天，中文显示
- 三级时间范围：24 小时（内存明细）、7 天、30 天（每日汇总落盘）
- LuCI 原生视图（不用 iframe），固定行高/表格高度，页签切换不跳动
- 常驻内存约 1.4 MB，纯 ash + awk，无额外依赖

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
| `scan_ports` | 5 | 60 秒内公网/UPnP 不同端口数达到多少算扫描 |
| `scan_conns` | 30 | 60 秒内公网端口连接数达到多少算高频 |
| `retain_days` | 30 | 每日汇总保留天数 |
| `alert_keep` | 5000 | 告警保留条数 |
| `conn_keep` | 50000 | 24h 连接明细条数上限（超出按时间淘汰） |
| `geo` | 1 | 是否查询来源 IP 归属地 |

改完执行 `/etc/init.d/guard restart` 生效。

**忽略名单**：`/etc/guard/ignore.list`，一行一个端口（`#` 注释），命中的端口归为正常、不计入关注；重启后生效。

## 分类口径

| 分类 | 含义 | 默认 |
|---|---|---|
| `L` | lucky 公网服务端口（nft accept + dstnat），且落点在 WAN 或路由器本机；落到内机的同号端口按 UPnP/回连判 | 关注 |
| `U` | UPnP 映射端口（内机应用） | 正常 |
| `B` | 无规则映射、落到内机的回连（P2P/视频） | 正常 |
| `P` | 未落到内机的探测 | 关注 |
| `N` | `ignore.list` 命中 | 正常 |

## 数据与留存

| 内容 | 位置 | 留存 |
|---|---|---|
| 连接明细 / 来源 / 暴露面清单（24h） | `/tmp/guard/` | 内存，重启清零 |
| 每日汇总（含主要落点/落点连接数） | `/etc/guard/daily/YYYY-MM-DD.tsv` | `retain_days` 天 |
| 告警记录 | `/etc/guard/alerts.tsv`、`alerts.log` | `alert_keep` 条 |
| 归属地缓存 | `/tmp/guard/geo.tsv` | 7 天 |

每日汇总每小时刷新一次，跨天时定稿；重启后自动读取当天已有汇总作为基线继续累计。日汇总从 v1.1.2 起增加「主要落点 + 落点连接数」，7/30 天视图按天累加后选主要落点；升级前的历史日汇总没有这两列，对应行会显示 `—`。明细达到 `conn_keep` 上限时页面显示「已封顶」，并给出实际覆盖时长。

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

- 只读取 `/proc/net/nf_conntrack` 与 nft 链，不修改任何规则
- 默认口径是「只看关注 + 全部协议」；P2P 的 UDP 对端数量很大，可在「含正常流量」里切「仅 TCP」过滤
- 归属地查询会把来源公网 IP 发往 ip-api.com，可设 `option geo '0'` 关闭
- 刷固件前请备份 `/etc/guard`（不在 sysupgrade 默认保留清单里）

## License

MIT
