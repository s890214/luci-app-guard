# luci-app-guard

OpenWrt / ImmortalWrt 上的**外部访问监控**插件：基于 conntrack 采样，记录所有打到 WAN 的入站连接，识别端口扫描和高频连接，按天汇总保留 30 天。**只记录，不封禁**，不改任何防火墙规则。

## 功能

- 全端口监控：任何入站连接都记录，不依赖端口清单；对外端口自动从 nft（`lucky666.cn_auto` + `dstnat_wan`）同步，用于标注
- 两类告警（阈值可配）：60 秒内 ≥N 个不同端口 = 端口扫描；≥M 次连接 = 高频
- 三级时间范围：24 小时（内存明细）、7 天、30 天（每日汇总落盘）
- 列表固定每页 12 条、行高 40px，表格区固定高度（不足也留白），页脚不跳动
- LuCI 原生视图（自己的样式 + E() 渲染，不用 iframe），保留主题头部
- 常驻内存约 1.3 MB，纯 ash + awk，无额外依赖

## 安装

```sh
# 方式一：复制本目录到路由器后执行
scp -r luci-app-guard root@192.168.1.1:/tmp/
ssh root@192.168.1.1 'sh /tmp/luci-app-guard/install.sh'

# 方式二：OpenWrt SDK 编译
# 将本目录放入 package/ 后 make menuconfig（LuCI → Applications → luci-app-guard）
```

安装后从 LuCI 菜单「服务 → 外部访问监控」进入（`/cgi-bin/luci/admin/services/guard`）。`/guard/` 会自动跳转到该页面。

## 配置

`/etc/config/guard`：

| 选项 | 默认 | 说明 |
|---|---|---|
| `enabled` | 1 | 是否启用 |
| `interval` | 10 | 采样间隔（秒） |
| `scan_ports` | 5 | 60 秒内不同端口数达到多少算扫描 |
| `scan_conns` | 30 | 60 秒内连接数达到多少算高频 |
| `retain_days` | 30 | 每日汇总保留天数 |
| `alert_keep` | 5000 | 告警保留条数 |

改完执行 `/etc/init.d/guard restart` 生效。

## 数据与留存

| 内容 | 位置 | 留存 |
|---|---|---|
| 连接明细 / 来源汇总（24h） | `/tmp/guard/` | 内存，重启清零 |
| 每日汇总 | `/etc/guard/daily/YYYY-MM-DD.tsv` | `retain_days` 天 |
| 告警记录 | `/etc/guard/alerts.tsv`、`alerts.log` | `alert_keep` 条 |

每日汇总每小时刷新一次，跨天时定稿；重启后自动读取当天已有汇总作为基线继续累计。

## 接口

`/cgi-bin/guard?view=summary` — 概览
`/cgi-bin/guard?view=sources&range=24h|7d|30d&page=1&size=50` — 来源
`/cgi-bin/guard?view=alerts&range=...&page=...` — 告警
`/cgi-bin/guard?view=events&page=...&proto=tcp|all` — 最近连接（24h）

## 卸载

```sh
/etc/init.d/guard stop
/etc/init.d/guard disable
rm -f /etc/init.d/guard /etc/guard/guard.sh /www/cgi-bin/guard \
      /www/guard/index.html /usr/share/luci/menu.d/luci-app-guard.json
rm -rf /etc/guard
```

## 说明

- 只读取 `/proc/net/nf_conntrack` 与 nft 链，不修改任何规则
- 迅雷/qB 等 P2P 的 UDP 对端数量很大，默认统计口径为 TCP，UDP 仅计数展示
- 刷固件前请备份 `/etc/guard`（不在 sysupgrade 默认保留清单里）

## License

MIT
