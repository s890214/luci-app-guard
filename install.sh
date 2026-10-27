#!/bin/sh
# luci-app-guard 一键安装（在路由器上执行）
set -e
SRC=$(cd "$(dirname "$0")" && pwd)

[ -d "$SRC/root" ] || { echo "缺少 root/ 目录"; exit 1; }

cp -r "$SRC/root/." /
rm -f /www/cgi-bin/guard
rm -rf /www/guard
chmod 755 /etc/guard/guard.sh /etc/init.d/guard /usr/lib/guard/guard-cgi
chmod 644 /etc/config/guard /www/luci-static/resources/view/guard/overview.js \
	/usr/lib/guard/class.awk /usr/lib/lua/luci/controller/guard.lua
mkdir -p /etc/guard/daily /etc/guard/detail

/etc/init.d/guard enable
/etc/init.d/guard restart

echo "已安装。LuCI：服务 → 外部访问监控"
echo "地址：http://$(uci -q get network.lan.ipaddr || echo 192.168.1.1)/cgi-bin/luci/admin/services/guard"
