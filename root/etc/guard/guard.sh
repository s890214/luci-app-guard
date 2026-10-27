#!/bin/sh
# luci-app-guard 采集守护（只记录，不封禁）
# 数据源：/proc/net/nf_conntrack，只取原始方向 dst=WAN 的入站连接
# 只保留：L = 公网服务/端口转发；U = UPnP 映射
# 丢弃：P2P/fullcone 回连、被防火墙拒绝的探测、ignore.list 命中
# 留存：L/U 明细 24h（内存）；按天汇总落盘 retain_days 天；告警 alert_keep 条

cfg() { v=$(uci -q get "guard.main.$1" 2>/dev/null); [ -z "$v" ] && v=$2; echo "$v"; }

DIR=${GUARD_DIR:-/tmp/guard}
DATA=${GUARD_DATA:-/etc/guard}
ALERTS=$DATA/alerts.tsv
DAILY=$DATA/daily
CTFILE=${GUARD_CONNTRACK:-/proc/net/nf_conntrack}
WANIF=${GUARD_WANIF:-$(cfg wan_if pppoe-wan)}
LIB=${GUARD_LIB:-/usr/lib/guard/class.awk}
TAB=$(printf '\t')

INTERVAL=${GUARD_INTERVAL:-$(cfg interval 5)}
SCAN_PORTS=$(cfg scan_ports 5)
SCAN_CONNS=$(cfg scan_conns 30)
RETAIN_DAYS=$(cfg retain_days 30)
ALERT_KEEP=$(cfg alert_keep 5000)
CONN_KEEP=$(cfg conn_keep 50000)
GEO_ENABLE=${GUARD_GEO:-$(cfg geo 1)}
HOURLY=${GUARD_HOURLY:-3600}
LANIP=${GUARD_LANIP:-$(uci -q get network.lan.ipaddr 2>/dev/null)}
LANIP=${LANIP%%/*}
[ -z "$LANIP" ] && LANIP=192.168.1.1
[ "$(cfg enabled 1)" = "0" ] && exit 0

mkdir -p "$DIR" "$DATA" "$DAILY"
touch "$DIR/conn.log" "$DIR/seen.ts" "$DIR/alerted" "$DIR/alerts.tsv" "$DIR/start.ts" \
	"$DIR/ips.tsv" "$DIR/ports.tsv" "$DIR/hosts.tsv" "$DIR/upnp.tsv" "$DIR/geo.tsv" \
	"$DIR/ignore.list" "$DIR/exposed.txt" "$DIR/exposed.map" "$ALERTS"
[ -f "$DATA/ignore.list" ] && cp "$DATA/ignore.list" "$DIR/ignore.list"

# 内机 IP -> 设备名（静态租约优先，其次动态租约）
sync_hosts() {
	{
		uci -q show dhcp 2>/dev/null | awk -F"'" '
			/^dhcp\.@host\[[0-9]+\]\.(ip|name)=/ {
				split($1, a, "."); key = a[2]
				if ($1 ~ /\.ip=/) ip[key] = $2; else nm[key] = $2
			}
			END { for (k in ip) if ((k in nm) && ip[k] != "" && nm[k] != "") print ip[k] "\t" nm[k] }'
		[ -s /tmp/dhcp.leases ] && awk '$3 != "" && $4 != "" && $4 != "*" { print $3 "\t" $4 }' /tmp/dhcp.leases
		printf '%s\t%s\n' "$LANIP" "路由器"
	} | awk -F'\t' 'NF >= 2 && !seen[$1]++' > "$DIR/hosts.tsv"
}

# UPnP 租约：PROTO:外口:内机:内口:到期:描述
sync_upnp() {
	awk -F: 'NF >= 6 { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $6 }' \
		/var/run/miniupnpd.leases 2>/dev/null | sort -u > "$DIR/upnp.tsv"
}

# 公网服务清单：lucky 自动放行 + dstnat 转发 + 手动 fw4 ACCEPT 规则
# exposed.map：协议 \t 外部端口 \t 内网落点 \t 内网端口 \t 来源说明
sync_ports() {
	{
		for ch in $(nft list chains 2>/dev/null | awk '/chain .*_auto/ { print $2 }'); do
			nft list chain inet fw4 "$ch" 2>/dev/null | awk -v lan="$LANIP" '
				/dport [0-9]+ accept/ {
					pr = ""; dp = ""
					for (i = 1; i <= NF; i++) {
						if ($i == "tcp" || $i == "udp") pr = $i
						if ($i == "dport") dp = $(i + 1)
					}
					if (pr != "" && dp != "")
						printf "%s\t%s\t%s\t%s\t%s\n", pr, dp, lan, dp, "lucky 公网服务"
				}'
		done

		nft list chain inet fw4 dstnat_wan 2>/dev/null | awk '
			/dnat ip to/ {
				pr = ""; dp = ""; tgt = ""
				for (i = 1; i <= NF; i++) {
					if ($i == "tcp" || $i == "udp") pr = $i
					if ($i == "dport") dp = $(i + 1)
					if ($i == "to") tgt = $(i + 1)
				}
				if (pr != "" && dp != "" && tgt != "") {
					n = split(tgt, a, ":")
					printf "%s\t%s\t%s\t%s\t%s\n", pr, dp, a[1], (n > 1 ? a[2] : dp), "端口转发"
				}
			}'

		uci -q show firewall 2>/dev/null | awk -F"'" -v lan="$LANIP" '
			/^firewall\.@rule\[[0-9]+\]\./ {
				split($1, p, "."); key = p[2]; f = p[3]; v = $2
				if (f == "src") src[key] = v
				else if (f == "proto") proto[key] = v
				else if (f == "dest_port") dport[key] = v
				else if (f == "dest_ip") dip[key] = v
				else if (f == "target") tgt[key] = v
				keys[key] = 1
			}
			END {
				for (k in keys) {
					if (src[k] != "wan" || tgt[k] != "ACCEPT" || dport[k] == "") continue
					tip = (dip[k] != "" ? dip[k] : lan)
					n = split(dport[k], a, " ")
					m = split(proto[k], pr, " ")
					if (proto[k] == "" || proto[k] == "all") { pr[1] = "tcp"; pr[2] = "udp"; m = 2 }
					for (i = 1; i <= m; i++) {
						for (j = 1; j <= n; j++) {
							if (a[j] ~ /^(68|546|500|4500)$/) continue
							if (a[j] ~ /-/) continue
							printf "%s\t%s\t%s\t%s\t%s\n", pr[i], a[j], tip, a[j], "防火墙规则"
						}
					}
				}
			}'
	} | sort -u > "$DIR/exposed.map"
	# 同一 协议+端口+落点 只保留一条（lucky 与 dstnat 常对同一端口各出一条）
	awk -F'	' '!seen[$1 "|" $2 "|" $3]++' "$DIR/exposed.map" > "$DIR/exposed.map.tmp" && mv "$DIR/exposed.map.tmp" "$DIR/exposed.map"
	awk -F'	' '{ print $2 }' "$DIR/exposed.map" | sort -un | tr '\n' ' ' > "$DIR/exposed.txt"
}

# 按 IP 聚合（只统计 L/U）：
# ip total tcp udp ports portlist first last l24 l60 sc60 sclist lplist topdst topdst_n
aggregate() {
	awk -v MAPDIR="$DIR" -v now="$2" -v wanip="$3" -v since="$4" -v LANIP="$5" "$(cat "$LIB")"'
		{
			t = $1; ip = $2; dp = $3; pr = $4; c = $6; dst = $7
			mk = toupper(pr) "|" dp
			if (dst == "" || dst == "-")
				dsp = (mk in LMAP ? LMAP[mk] : (mk in UPIP ? UPIP[mk] : LANIP))
			else if (dst == wanip)
				dsp = LANIP
			else
				dsp = dst

			if (t >= since) {
				total[ip]++
				if (pr == "tcp") tcp[ip]++; else udp[ip]++
				if (!(ip in first) || t < first[ip]) first[ip] = t
				if (t > last[ip]) last[ip] = t
				if (!((ip "|" dp) in pseen)) {
					pseen[ip "|" dp] = 1; pc[ip]++
					if (pc[ip] <= 12) pl[ip] = pl[ip] (pl[ip] == "" ? "" : ",") dp
				}
				dc[ip "|" dsp]++
				if (dc[ip "|" dsp] > topv[ip]) { topv[ip] = dc[ip "|" dsp]; topd[ip] = dsp }
				if (c == "L") l24[ip]++
			}

			if (t >= now - 60) {
				if (c == "L") l60[ip]++
				if (c == "L" || c == "U") {
					if (!((ip "|" dp) in scseen)) {
						scseen[ip "|" dp] = 1; scc[ip]++
						scl[ip] = scl[ip] (scl[ip] == "" ? "" : ",") dp
					}
					if (c == "L" && !((ip "|" dp) in lpseen)) {
						lpseen[ip "|" dp] = 1; lpc[ip]++
						if (lpc[ip] <= 8) lpl[ip] = lpl[ip] (lpl[ip] == "" ? "" : ",") dp
					}
				}
			}
		}
		END {
			for (ip in total)
				printf "%s\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%d\n",
					ip, total[ip], tcp[ip], udp[ip], pc[ip], pl[ip], first[ip], last[ip],
					l24[ip], l60[ip], scc[ip], scl[ip], lpl[ip], topd[ip], topv[ip]
		}' "$1"
}

# 按落点聚合：优先级 class 连接数 来源数 最近 落点 端口 协议 描述
# 先汇总 24h 有流量的端口，再补上 exposed.map/upnp 清单里无流量的库存行。
aggregate_ports() {
	awk -v MAPDIR="$DIR" -v now="$1" -v wanip="$2" -v LANIP="$3" "$(cat "$LIB")"'
		{
			t = $1
			if (t < now - 86400) next
			ip = $2; dp = $3; pr = $4; c = $6; dst = $7
			mk = toupper(pr) "|" dp
			if (dst == "" || dst == "-")
				dsp = (mk in LMAP ? LMAP[mk] : (mk in UPIP ? UPIP[mk] : LANIP))
			else if (dst == wanip)
				dsp = LANIP
			else
				dsp = dst

			k = dsp "|" dp "|" pr
			cnt[k]++
			if (!((k "|" ip) in seen)) { seen[k "|" ip] = 1; sc[k]++ }
			if (t > last[k]) last[k] = t
			cl[k] = c
		}
		END {
			for (k in cnt) {
				split(k, a, "|")
				printf "%d\t%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\n",
					prio(cl[k]) * 1000000 - cnt[k], cl[k], cnt[k], sc[k], last[k],
					a[1], a[2], a[3], (cl[k] == "L" ? ldesc(a[3], a[2]) : updesc(a[3], a[2]))
			}
		}' "$DIR/conn.log" > "$DIR/ports.new"

	awk -F'\t' -v dir="$DIR" '
		{
			print
			seen[$6 "|" $7 "|" $8] = 1
		}
		END {
			while ((getline l < (dir "/exposed.map")) > 0) {
				split(l, a, "\t")
				if (a[1] == "" || a[2] == "") continue
				k = a[3] "|" a[2] "|" a[1]
				if (k in seen) continue
				seen[k] = 1
				print "0\tL\t0\t0\t0\t" a[3] "\t" a[2] "\t" a[1] "\t" a[5]
			}
			while ((getline l < (dir "/upnp.tsv")) > 0) {
				split(l, a, "\t")
				if (a[1] == "" || a[2] == "") continue
				pr = tolower(a[1])
				k = a[3] "|" a[2] "|" pr
				if (k in seen) continue
				seen[k] = 1
				print "1000000\tU\t0\t0\t0\t" a[3] "\t" a[2] "\t" pr "\t" a[5]
			}
		}' "$DIR/ports.new" | sort -t "$TAB" -k1 -n | head -n 800 > "$DIR/ports.tsv"
	rm -f "$DIR/ports.new"
}

# 落盘当天汇总：基线(重启前) + 今日实时，按 IP 合并
# 日汇总格式：ip tcp udp ports portlist first last [topdst topdst_n]
write_daily() {
	[ -s "$DIR/today.tsv" ] || return 0
	awk -F'\t' '
		FILENAME == ARGV[1] { base[$1] = $0; next }
		{ cur[$1] = $0 }
		END {
			for (ip in base) {
				if (ip in cur) continue
				split(base[ip], x, "\t")
				printf "%s\t%d\t%d\t%d\t%s\t%d\t%d", ip, x[2] + 0, x[3] + 0, x[4] + 0, x[5], x[6] + 0, x[7] + 0
				if (x[8] != "" && x[8] != "-") printf "\t%s\t%d", x[8], x[9] + 0
				printf "\n"
			}
			for (ip in cur) {
				split(cur[ip], c, "\t")
				tcp = c[3] + 0; udp = c[4] + 0
				pl = c[6]; first = c[7] + 0; last = c[8] + 0
				dst = c[14]; dn = c[15] + 0
				if (ip in base) {
					split(base[ip], x, "\t")
					tcp += x[2]; udp += x[3]
					n = split(x[5], xp, ",")
					for (i = 1; i <= n; i++)
						if (xp[i] != "" && index("," pl ",", "," xp[i] ",") == 0)
							pl = pl (pl == "" ? "" : ",") xp[i]
					if (first == 0 || (x[6] + 0 > 0 && x[6] + 0 < first)) first = x[6] + 0
					if (x[7] + 0 > last) last = x[7] + 0
					if (x[8] != "" && x[8] != "-" && (dst == "" || x[9] + 0 > dn)) { dst = x[8]; dn = x[9] + 0 }
				}
				n = split(pl, pp, ","); ports = 0
				for (i = 1; i <= n; i++) if (pp[i] != "") ports++
				printf "%s\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\n", ip, tcp, udp, ports, pl, first, last, dst, dn
			}
		}' "$DIR/baseline.tsv" "$DIR/today.tsv" > "$DAILY/$1.tsv.tmp"
		if cmp -s "$DAILY/$1.tsv.tmp" "$DAILY/$1.tsv"; then
			rm -f "$DAILY/$1.tsv.tmp"
		else
			mv "$DAILY/$1.tsv.tmp" "$DAILY/$1.tsv"
		fi
		find "$DAILY" -name '*.tsv' -mtime +"$RETAIN_DAYS" -exec rm -f {} \; 2>/dev/null
}

# 归属地：只查 L/U 来源里连接数前 120 + 24h 告警来源；缓存 7 天；每小时最多 100 个
geo_refresh() {
	[ "$GEO_ENABLE" = "1" ] || return 0
	[ -s "$DIR/ips.tsv" ] || return 0
	now=$(date +%s)
	awk -F'\t' -v cut=$((now - 604800)) '$6 >= cut' "$DIR/geo.tsv" > "$DIR/geo.tmp" 2>/dev/null && mv "$DIR/geo.tmp" "$DIR/geo.tsv"
	{
		awk -F'\t' 'NR <= 120 || $9 > 0 { print $1 }' "$DIR/ips.tsv"
		awk -F'|' -v cut=$((now - 86400)) '$1 >= cut { print $3 }' "$ALERTS" 2>/dev/null
	} | awk 'NF && !seen[$0]++' > "$DIR/geo.want"
	awk 'FILENAME == ARGV[1] { seen[$1] = 1; next } !($1 in seen)' "$DIR/geo.tsv" "$DIR/geo.want" | head -n 100 > "$DIR/geo.miss"
	[ -s "$DIR/geo.miss" ] || return 0
	body=$(awk 'BEGIN { printf "[" } NR > 1 { printf "," } { printf "\"%s\"", $1 } END { printf "]" }' "$DIR/geo.miss")
	[ -n "$body" ] || return 0
	resp=$(curl -m 8 -s -X POST -H "Content-Type: application/json" -d "$body" \
		"http://ip-api.com/batch?fields=query,country,regionName,isp,as&lang=zh-CN" 2>/dev/null)
	[ -n "$resp" ] || return 0
	printf '%s' "$resp" | awk -v now="$now" '
		{
			line = $0
			gsub(/\},\{/, "\n", line)
			n = split(line, rec, "\n")
			for (j = 1; j <= n; j++) {
				r = rec[j]
				gsub(/^\[/, "", r); gsub(/\]$/, "", r); gsub(/^[{]/, "", r); gsub(/[}]$/, "", r)
				m = split(r, p, "\",\"")
				q = cy = rg = isp = asn = ""
				for (i = 1; i <= m; i++) {
					split(p[i], kv, "\":\"")
					k = kv[1]; gsub(/^[\",{]+/, "", k)
					v = kv[2]; gsub(/[\"\r\n]/, "", v); gsub(/\t/, " ", v)
					if (k == "query") q = v
					else if (k == "country") cy = v
					else if (k == "regionName") rg = v
					else if (k == "isp") isp = v
					else if (k == "as") asn = v
				}
				if (q != "") printf "%s\t%s\t%s\t%s\t%s\t%d\n", q, cy, rg, isp, asn, now
			}
		}' > "$DIR/geo.add"
	[ -s "$DIR/geo.add" ] || { rm -f "$DIR/geo.add"; return 0; }
	awk -F'\t' 'FILENAME == ARGV[1] { a[$1] = $0; next } { a[$1] = $0 } END { for (k in a) print a[k] }' \
		"$DIR/geo.tsv" "$DIR/geo.add" > "$DIR/geo.tmp" && mv "$DIR/geo.tmp" "$DIR/geo.tsv"
	rm -f "$DIR/geo.add"
}

# 概览 JSON（页面头部）
build_state() {
	now=$1; wan=$2
	stats=$(awk -v now="$now" '
		{
			tot++
			if ($4 == "tcp") { tcp++; st[$2] = 1 } else { udp++; su[$2] = 1 }
			src[$2] = 1
			if ($1 >= now - 86400 && $6 == "L") w24++
		}
		END { printf "%d %d %d %d %d %d %d", tot, tcp, udp, length(src), length(st), length(su), w24 }
	' "$DIR/conn.log")
	[ -z "$stats" ] && stats="0 0 0 0 0 0 0"
	set -- $stats
	tot=$1; tcp24=$2; udp24=$3; src24=$4; srctcp=$5; srcudp=$6; w24=$7

	first=$(head -n 1 "$DIR/conn.log" 2>/dev/null | awk '{ print $1 }')
	[ -z "$first" ] && first=$(cat "$DIR/start.ts" 2>/dev/null)
	[ -z "$first" ] && first=$now
	span=$(( (now - first) / 60 ))
	[ "$span" -lt 0 ] && span=0
	[ "$span" -gt 1440 ] && span=1440
	capped=0
	[ "$tot" -ge "$CONN_KEEP" ] && capped=1
	alerts24=$(awk -F'|' -v n="$now" '$1 + 0 >= n - 86400 { c++ } END { print c + 0 }' "$ALERTS")

	printf '{"ts":%s,"human":"%s","wan":"%s","lan":"%s","uptime":%s,"exposed":"%s","stats":{"total24":%d,"tcp24":%d,"udp24":%d,"src24":%d,"srctcp":%d,"srcudp":%d,"watch24":%d,"alerts24":%d,"span_m":%d,"capped":%d}}' \
		"$now" "$(date -d "@$now" +'%Y-%m-%d %H:%M:%S')" "$wan" "$LANIP" "$(cut -d. -f1 /proc/uptime)" \
		"$(cat "$DIR/exposed.txt" 2>/dev/null)" \
		"$tot" "$tcp24" "$udp24" "$src24" "$srctcp" "$srcudp" "$w24" "$alerts24" "$span" "$capped" \
		> "$DIR/state.json.tmp" && mv "$DIR/state.json.tmp" "$DIR/state.json"
}

# 重启后若内存明细为空、当天已有落盘汇总，用它做基线
TODAY=$(date +%F)
if [ ! -s "$DIR/conn.log" ] && [ -s "$DAILY/$TODAY.tsv" ]; then
	cp "$DAILY/$TODAY.tsv" "$DIR/baseline.tsv"
else
	: > "$DIR/baseline.tsv"
fi
[ -s "$DIR/start.ts" ] || date +%s > "$DIR/start.ts"

last_min=0
last_hour=0
last_geo=0
cur_day=$TODAY
rmdir "$DIR/geo.lock" 2>/dev/null
sync_ports
sync_hosts
sync_upnp

while :; do
	now=$(date +%s)
	day=$(date +%F)
	wan=$(ip -4 addr show "$WANIF" 2>/dev/null | awk '/inet /{ print $2 }' | cut -d/ -f1)

	if [ "$day" != "$cur_day" ]; then
		write_daily "$cur_day"
		: > "$DIR/baseline.tsv"
		cur_day=$day
	fi

	if [ -n "$wan" ]; then
		# 原始方向 + 回复方向 src（DNAT 后的真实落点）；UNREPLIED 用 "-" 占位
		awk -v wan="$wan" '
			{ src = ""; dst = ""; sp = ""; dp = ""; rsrc = ""; nsrc = 0; pr = $3
			  for (i = 1; i <= NF; i++) {
			    if ($i ~ /^src=/) {
			      nsrc++; split($i, a, "=")
			      if (nsrc == 1) { if (src == "") src = a[2] }
			      else if (nsrc == 2 && rsrc == "") rsrc = a[2]
			    }
			    else if (dst == "" && $i ~ /^dst=/)   { split($i, b, "="); dst = b[2] }
			    else if (sp == ""  && $i ~ /^sport=/) { split($i, c, "="); sp = c[2] }
			    else if (dp == ""  && $i ~ /^dport=/) { split($i, d, "="); dp = d[2] }
			  }
			  if (dst == wan && src != "" && dp != "") print src, sp, dp, pr, (rsrc == "" ? "-" : rsrc)
			}' "$CTFILE" 2>/dev/null \
		| awk '$1 !~ /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/' > "$DIR/ext.txt"

		# 入库前分类：只留 L/U，B（P2P 回连）/P（被拒绝/未落地）/N（忽略）直接丢弃
		awk -v now="$now" -v MAPDIR="$DIR" -v LANIP="$LANIP" "$(cat "$LIB")"'
			FILENAME == ARGV[1] { seen[$2] = 1; next }
			{
				c = cls($3, $4, $5)
				if (c != "L" && c != "U") next
				k = $1 "|" $2 "|" $3
				if (!(k in seen))
					printf "%d %s %s %s %s %d %s %s\n", now, $1, $2, $3, $4, (c == "L"), c, $5
			}' "$DIR/seen.ts" "$DIR/ext.txt" > "$DIR/new.txt"

		if [ -s "$DIR/new.txt" ]; then
			awk '{ print $1, $2, $4, $5, $6, $7, $8 }' "$DIR/new.txt" >> "$DIR/conn.log"
			awk '{ print $1, $2 "|" $3 "|" $4 }' "$DIR/new.txt" >> "$DIR/seen.ts"
		fi
	fi

	if [ $((now - last_min)) -ge 60 ]; then
		last_min=$now
		sync_hosts
		sync_upnp

		awk -v cut=$((now - 900)) '$1 >= cut' "$DIR/seen.ts" > "$DIR/seen.tmp" && mv "$DIR/seen.tmp" "$DIR/seen.ts"
		awk -v cut=$((now - 86400)) '$1 >= cut' "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"
		tail -n "$CONN_KEEP" "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"

		start_day=$(date -d "$day 00:00:00" +%s 2>/dev/null)
		[ -z "$start_day" ] && start_day=$((now - 86400))

		aggregate "$DIR/conn.log" "$now" "$wan" "$((now - 86400))" "$LANIP" \
			| awk -F'\t' '{ printf "%012d\t%s\n", $2, $0 }' | sort -k1 -nr | cut -f2- > "$DIR/ips.tsv.tmp" && mv "$DIR/ips.tsv.tmp" "$DIR/ips.tsv"
		aggregate "$DIR/conn.log" "$now" "$wan" "$start_day" "$LANIP" \
			| awk -F'\t' '{ printf "%012d\t%s\n", $2, $0 }' | sort -k1 -nr | cut -f2- > "$DIR/today.tsv.tmp" && mv "$DIR/today.tsv.tmp" "$DIR/today.tsv"
		aggregate_ports "$now" "$wan" "$LANIP"

		: > "$DIR/cand.txt"
		awk -F'\t' -v sp="$SCAN_PORTS" -v sc="$SCAN_CONNS" '
			$11 >= sp { printf "PORT_SCAN\t%s\t%d\t%s\n", $1, $11, $12 }
			$10 >= sc { printf "HIGH_RATE\t%s\t%d\t%s\n", $1, $10, $13 }
		' "$DIR/ips.tsv" >> "$DIR/cand.txt"

		if [ -s "$DIR/cand.txt" ]; then
			awk -v now="$now" '
				FILENAME == ARGV[1] { last[$1] = $2; next }
				{ k = $1 "|" $2; if (!(k in last) || now - last[k] >= 600) print }
			' "$DIR/alerted" "$DIR/cand.txt" > "$DIR/alerts.new"

			if [ -s "$DIR/alerts.new" ]; then
				while IFS="$TAB" read -r type ip cnt ports; do
					echo "$now|$type|$ip|$cnt|$ports" >> "$ALERTS"
				done < "$DIR/alerts.new"
				awk -v now="$now" '{ print $1 "|" $2, now }' "$DIR/cand.txt" >> "$DIR/alerted"
			fi
		fi
		awk -v cut=$((now - 900)) '$2 >= cut' "$DIR/alerted" > "$DIR/alerted.tmp" && mv "$DIR/alerted.tmp" "$DIR/alerted"
		if [ "$(wc -l < "$ALERTS")" -gt "$ALERT_KEEP" ]; then
			tail -n "$ALERT_KEEP" "$ALERTS" > "$ALERTS.tmp" && mv "$ALERTS.tmp" "$ALERTS"
		fi

		if [ $((now - last_hour)) -ge "$HOURLY" ]; then
			last_hour=$now
			sync_ports
			write_daily "$day"
		fi

		if [ $((now - last_geo)) -ge 3600 ]; then
			last_geo=$now
			if mkdir "$DIR/geo.lock" 2>/dev/null; then
				( geo_refresh; rmdir "$DIR/geo.lock" ) &
			fi
		fi

		build_state "$now" "$wan"
	fi

	sleep "$INTERVAL"
done
