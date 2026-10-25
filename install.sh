#!/bin/sh
# luci-app-guard 一键安装（在路由器上执行）
set -e
SRC=$(cd "$(dirname "$0")" && pwd)

[ -d "$SRC/root" ] || { echo "缺少 root/ 目录"; exit 1; }

cp -r "$SRC/root/." /
chmod 755 /etc/guard/guard.sh /etc/init.d/guard /www/cgi-bin/guard
chmod 644 /www/guard/index.html /etc/config/guard /www/luci-static/resources/view/guard/overview.js
mkdir -p /etc/guard/daily

/etc/init.d/guard enable
/etc/init.d/guard restart

echo "已安装。页面：http://$(uci -q get network.lan.ipaddr || echo 192.168.1.1)/guard/"
echo "LuCI 菜单：服务 → 外部访问监控"
