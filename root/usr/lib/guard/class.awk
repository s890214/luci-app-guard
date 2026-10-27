# 连接分类公共库（guard.sh / CGI 拼接到主程序前使用）
# 输入依赖 $GUARD_DIR（默认 /tmp/guard）下由 guard.sh 生成的：
#   exposed.txt  公网服务端口（lucky 监听/转发）
#   upnp.tsv     协议 \t 外部端口 \t 内机 \t 内机端口 \t 描述
#   hosts.tsv    内机 IP \t 设备名
#   ignore.list  可选，一行一个端口（# 注释），命中的端口归为正常
#
# 分类：
#   L = lucky 公网服务端口（关注）
#   U = UPnP 映射端口（内机应用，正常）
#   B = 无规则映射、但落到内机的回连（P2P/视频，正常）
#   P = 未落到内机的探测（关注）
#   N = 忽略名单（正常）

function cls(dp, pr, dst,   k) {
	if (dp in IG) return "N"
	k = toupper(pr) "|" dp
	# 暴露端口只有落在 WAN 或路由器本机（.1）时才算公网服务；
	# 落到内机的同号端口可能是 UPnP/回连/转发，继续往下判，避免把摄像头流量标成 lucky。
	if ((dp in EX) && (dst == "" || dst == "-" || dst == "192.168.1.1" || dst !~ /^192\.168\./)) return "L"
	if (k in UP) return "U"
	if (dst != "" && dst != "-") return "B"
	if (dp in EX) return "L"
	return "P"
}

function updesc(pr, dp,   k) {
	k = toupper(pr) "|" dp
	return (k in UP) ? UP[k] : ""
}

function prio(c) {
	if (c == "L") return 0
	if (c == "P") return 1
	if (c == "U") return 2
	if (c == "B") return 3
	return 4
}

BEGIN {
	dir = (MAPDIR == "" ? "/tmp/guard" : MAPDIR)

	while ((getline l < (dir "/exposed.txt")) > 0) {
		n = split(l, e, " ")
		for (i = 1; i <= n; i++) if (e[i] != "") EX[e[i]] = 1
	}

	while ((getline l < (dir "/upnp.tsv")) > 0) {
		split(l, a, "\t")
		if (a[1] != "" && a[2] != "")
			UP[toupper(a[1]) "|" a[2]] = a[5]
	}

	while ((getline l < (dir "/hosts.tsv")) > 0) {
		split(l, a, "\t")
		if (a[1] != "" && a[2] != "") HOST[a[1]] = a[2]
	}

	while ((getline l < (dir "/ignore.list")) > 0) {
		sub(/#.*/, "", l)
		gsub(/[ \t\r]/, "", l)
		if (l != "") IG[l] = 1
	}
}
