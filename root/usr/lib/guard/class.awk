# 连接分类公共库（guard.sh / CGI 拼接到主程序前使用）
# 输入依赖 $GUARD_DIR（默认 /tmp/guard）下由 guard.sh 生成的：
#   exposed.map  协议 \t 外部端口 \t 内网落点 \t 内网端口 \t 来源说明
#                （lucky 公网端口 / dstnat 端口转发 / 手动 fw4 规则）
#   exposed.txt  仅有公网端口列表，供页面头部显示（兼容旧数据）
#   upnp.tsv     协议 \t 外部端口 \t 内机 \t 内机端口 \t 描述
#   hosts.tsv    内机 IP \t 设备名
#   ignore.list  可选，一行一个端口（# 注释），命中的端口不记录
#
# 只保留两类会被记录：
#   L = 公网服务/端口转发（关注）
#   U = UPnP 映射端口（内机软件自己开的入站口）
# 其余（P2P/fullcone 回连、被防火墙拒绝的探测、忽略名单）一律丢弃，不落盘。

function cls(dp, pr, dst,   k, t, u) {
	if (dp in IG) return "N"
	k = toupper(pr) "|" dp

	# UPnP 优先：同一端口同时有 lucky 规则时，按回复落点区分 U/L
	if (k in UP) {
		u = UPIP[k]
		if (dst == "" || dst == "-" || dst == u) return "U"
	}

	# 公网服务：目标必须是 WAN/路由器本机，或回复方向确实落在映射的内机。
	if (k in LMAP) {
		t = LMAP[k]
		if (t == "") return "L"
		if (t == LANIP) {
			# 路由器本机端口：回复来自别的内机时不是这条 lucky 映射
			if (dst == "" || dst == "-" || dst == LANIP || dst !~ /^192\.168\./) return "L"
		} else if (dst == "" || dst == "-" || dst == t) {
			return "L"
		}
		# 同号端口但落到别的内机：不是这条映射，继续按回连判
	}

	if (dst ~ /^192\.168\./ && dst != LANIP) return "B"
	return "P"
}

function updesc(pr, dp,   k) {
	k = toupper(pr) "|" dp
	return (k in UP) ? UP[k] : ""
}

function ldesc(pr, dp,   k) {
	k = toupper(pr) "|" dp
	return (k in LSRC) ? LSRC[k] : "公网服务"
}

function prio(c) {
	if (c == "L") return 0
	if (c == "U") return 1
	return 2
}

BEGIN {
	dir = (MAPDIR == "" ? "/tmp/guard" : MAPDIR)
	LANIP = (LANIP == "" ? "192.168.1.1" : LANIP)

	# 供 7/30 天视图和告警过滤使用的端口集合（只认端口，不区分协议）
	while ((getline l < (dir "/exposed.txt")) > 0) {
		n = split(l, e, " ")
		for (i = 1; i <= n; i++) if (e[i] != "") EX[e[i]] = 1
	}

	have = 0
	while ((getline l < (dir "/exposed.map")) > 0) {
		split(l, a, "\t")
		if (a[1] != "" && a[2] != "") {
			k = toupper(a[1]) "|" a[2]
			LMAP[k] = a[3]
			LSRC[k] = (a[5] == "" ? "公网服务" : a[5])
			have = 1
		}
	}
	# 旧部署没有 exposed.map 时的兜底：只认端口，落点按路由器
	if (!have) {
		while ((getline l < (dir "/exposed.txt")) > 0) {
			n = split(l, e, " ")
			for (i = 1; i <= n; i++) {
				if (e[i] == "") continue
				LMAP["TCP|" e[i]] = LANIP
				LMAP["UDP|" e[i]] = LANIP
				LSRC["TCP|" e[i]] = "公网服务"
				LSRC["UDP|" e[i]] = "公网服务"
			}
		}
	}

	while ((getline l < (dir "/upnp.tsv")) > 0) {
		split(l, a, "\t")
		if (a[1] != "" && a[2] != "") {
			k = toupper(a[1]) "|" a[2]
			UP[k] = a[5]
			UPIP[k] = a[3]
		}
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
