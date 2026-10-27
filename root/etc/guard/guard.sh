#!/bin/sh
# luci-app-guard 采集守护（只记录，不封禁）
# 数据源：/proc/net/nf_conntrack，只取原始方向 dst=WAN 的入站连接
# 端口归属：lucky 公网端口（nft accept + dstnat）/ UPnP 租约 / 无规则回连 / 未落地探测
# 留存：连接明细 24h（内存，conn_keep 条上限）；按天汇总落盘 retain_days 天；告警 alert_keep 条

DIR=${GUARD_DIR:-/tmp/guard}
DATA=${GUARD_DATA:-/etc/guard}
ALERTLOG=$DATA/alerts.log
ALERTS=$DATA/alerts.tsv
DAILY=$DATA/daily
CTFILE=${GUARD_CONNTRACK:-/proc/net/nf_conntrack}
WANIF=${GUARD_WANIF:-pppoe-wan}
LIB=${GUARD_LIB:-/usr/lib/guard/class.awk}
TAB=$(printf '\t')

cfg() { v=$(uci -q get "guard.main.$1" 2>/dev/null); [ -z "$v" ] && v=$2; echo "$v"; }
INTERVAL=${GUARD_INTERVAL:-$(cfg interval 5)}
SCAN_PORTS=$(cfg scan_ports 5)
SCAN_CONNS=$(cfg scan_conns 30)
RETAIN_DAYS=$(cfg retain_days 30)
ALERT_KEEP=$(cfg alert_keep 5000)
CONN_KEEP=$(cfg conn_keep 50000)
GEO_ENABLE=$(cfg geo 1)
HOURLY=${GUARD_HOURLY:-3600}
[ "$(cfg enabled 1)" = "0" ] && exit 0

mkdir -p "$DIR" "$DATA" "$DAILY"
touch "$DIR/conn.log" "$DIR/day.log" "$DIR/seen.ts" "$DIR/alerted" "$DIR/alerts.tsv" \
	"$DIR/ips.tsv" "$DIR/ports.tsv" "$DIR/hosts.tsv" "$DIR/upnp.tsv" "$DIR/geo.tsv" \
	"$DIR/ignore.list" "$ALERTS" "$ALERTLOG"
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
		echo "192.168.1.1	路由器"
	} | awk -F'\t' 'NF >= 2 && !seen[$1]++' > "$DIR/hosts.tsv"
}

# UPnP 租约：PROTO:外口:内机:内口:到期:描述
sync_upnp() {
	awk -F: 'NF >= 6 { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $6 }' \
		/var/run/miniupnpd.leases 2>/dev/null | sort -u > "$DIR/upnp.tsv"
}

# 公网服务端口：lucky 自动放行 + dstnat 静态转发
sync_ports() {
	{
		nft list chain inet fw4 lucky666.cn_auto 2>/dev/null | awk '/dport [0-9]+ accept/ { for (i=1;i<=NF;i++) if ($i=="dport") print $(i+1) }'
		nft list chain inet fw4 dstnat_wan 2>/dev/null | awk '/dnat/ { for (i=1;i<=NF;i++) if ($i=="dport") print $(i+1) }'
	} | sort -un | tr '\n' ' ' > "$DIR/exposed.txt"
}

# 按 IP 聚合：ip total first last ports c60 p60 portlist tcp udp l24 lports l60 sc60 topdst topclass sclist lplist topdst_n
aggregate() {
	awk -v MAPDIR="$DIR" -v now="$2" -v wanip="$3" "$(cat "$LIB")"'
		{
			t = $1; ip = $2; dp = $3; pr = $4; dst = $6; c = cls(dp, pr, dst)
			dsp = (dst == wanip ? "192.168.1.1" : dst)
			if (t >= now - 86400) {
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
				p = prio(c)
				if (!(ip in bestp) || p < bestp[ip]) { bestp[ip] = p; bestc[ip] = c }
				if (c == "L") {
					l24[ip]++
					if (!((ip "|" dp) in lpseen)) {
						lpseen[ip "|" dp] = 1; lpc[ip]++
						if (lpc[ip] <= 8) lpl[ip] = lpl[ip] (lpl[ip] == "" ? "" : ",") dp
					}
				}
			}
			if (t >= now - 60) {
				c60[ip]++
				if (!((ip "|" dp) in s60seen)) { s60seen[ip "|" dp] = 1; p60c[ip]++ }
				if (c == "L") l60[ip]++
				if (c == "L" || c == "U") {
					if (!((ip "|" dp) in scseen)) {
						scseen[ip "|" dp] = 1; scc[ip]++
						scl[ip] = scl[ip] (scl[ip] == "" ? "" : ",") dp
					}
				}
			}
		}
		END {
			for (ip in total)
				printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%s\t%d\n",
					ip, total[ip], first[ip], last[ip], pc[ip], c60[ip], p60c[ip], pl[ip],
					tcp[ip], udp[ip], l24[ip], lpc[ip], l60[ip], scc[ip],
					topd[ip], bestc[ip], scl[ip], lpl[ip], topv[ip]
		}' "$1"
}

# 按落点聚合：优先级 class 连接数 来源数 最近 落点 端口 协议 描述
# 先汇总 24h 有流量的端口，再补上 exposed/upnp 清单里 24h 没有流量的端口（count=0）。
aggregate_ports() {
	awk -v MAPDIR="$DIR" -v now="$1" -v wanip="$2" "$(cat "$LIB")"'
		{
			t = $1
			if (t < now - 86400) next
			ip = $2; dp = $3; pr = $4; dst = $6; c = cls(dp, pr, dst)
			dsp = (dst == wanip ? "192.168.1.1" : dst)
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
					prio(cl[k]) * 1000000 - cnt[k], cl[k], cnt[k], sc[k], last[k], a[1], a[2], a[3], updesc(a[3], a[2])
			}
		}' "$DIR/conn.log" > "$DIR/ports.new"

	# 补暴露面库存：lucky 端口 + UPnP 映射，即使 24h 无流量也列出来。
	awk -F'	' -v dir="$DIR" '
		{
			print
			seenL[$7] = 1
			seenU[$6 "|" $7 "|" $8] = 1
		}
		END {
			while ((getline l < (dir "/exposed.txt")) > 0) {
				n = split(l, e, " ")
				for (i = 1; i <= n; i++) {
					if (e[i] == "" || (e[i] in seenL)) continue
					print "0	L	0	0	0	192.168.1.1	" e[i] "	tcp	lucky 公网服务"
				}
			}
			while ((getline l < (dir "/upnp.tsv")) > 0) {
				split(l, a, "	")
				if (a[1] == "" || a[2] == "") continue
				pr = tolower(a[1])
				k = a[3] "|" a[2] "|" pr
				if (k in seenU) continue
				seenU[k] = 1
				print "2000000	U	0	0	0	" a[3] "	" a[2] "	" pr "	" a[5]
			}
		}' "$DIR/ports.new" | sort -t "$TAB" -k1 -n | head -n 800 > "$DIR/ports.tsv"
	rm -f "$DIR/ports.new"
}

# 落盘当天汇总：基线(重启前) + 今日实时，按 IP 合并
# 日汇总格式：ip tcp udp ports portlist first last [topdst topdst_n]
# 旧文件只有前 7 列；新文件补主要落点和该落点的连接数，供 7/30 天视图选落点。
write_daily() {
	[ -s "$DIR/today.tsv" ] || return 0
	awk -F'\t' '
		FILENAME == ARGV[1] { base[$1] = $0; next }
		{ cur[$1] = $0 }
		END {
			# 基线里有、当天实时已没有的 IP 也要保留（重启后不会丢）
			for (ip in base) {
				if (ip in cur) continue
				split(base[ip], x, "\t")
				printf "%s\t%d\t%d\t%d\t%s\t%d\t%d", ip, x[2] + 0, x[3] + 0, x[4] + 0, x[5], x[6] + 0, x[7] + 0
				if (x[8] != "" && x[8] != "-") printf "\t%s\t%d", x[8], x[9] + 0
				printf "\n"
			}
			for (ip in cur) {
				split(cur[ip], c, "\t")
				tcp = c[9] + 0; udp = c[10] + 0; ports = c[5] + 0
				pl = c[8]; first = c[3] + 0; last = c[4] + 0
				dst = c[15]; dn = c[19] + 0
				if (ip in base) {
					split(base[ip], x, "\t")
					tcp += x[2]; udp += x[3]; ports += x[4]
					n = split(x[5], xp, ",")
					for (i = 1; i <= n; i++)
						if (xp[i] != "" && index("," pl ",", "," xp[i] ",") == 0)
							pl = pl (pl == "" ? "" : ",") xp[i]
					if (first == 0 || (x[6] + 0 > 0 && x[6] + 0 < first)) first = x[6] + 0
					if (x[7] + 0 > last) last = x[7] + 0
					# 同一天基线/实时都有落点时，取落点连接数更大的那个
					if (x[8] != "" && x[8] != "-" && (dst == "" || x[9] + 0 > dn)) { dst = x[8]; dn = x[9] + 0 }
				}
				printf "%s\t%d\t%d\t%d\t%s\t%d\t%d\t%s\t%d\n", ip, tcp, udp, ports, pl, first, last, dst, dn
			}
		}' "$DIR/baseline.tsv" "$DIR/today.tsv" > "$DAILY/$1.tsv.tmp" && mv "$DAILY/$1.tsv.tmp" "$DAILY/$1.tsv"
	find "$DAILY" -name '*.tsv' -mtime +"$RETAIN_DAYS" -delete 2>/dev/null
}

# 归属地：只查连接数前 120 的来源，缓存 7 天；每小时最多一批（100 个）
geo_refresh() {
	[ "$GEO_ENABLE" = "1" ] || return 0
	[ -s "$DIR/ips.tsv" ] || return 0
	now=$(date +%s)
	awk -F'\t' -v cut=$((now - 604800)) '$6 >= cut' "$DIR/geo.tsv" > "$DIR/geo.tmp" 2>/dev/null && mv "$DIR/geo.tmp" "$DIR/geo.tsv"
	{
		awk -F'\t' 'NR <= 120 || $11 > 0 { print $1 }' "$DIR/ips.tsv"
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
					k = kv[1]; gsub(/^[",{]+/, "", k)
					v = kv[2]; gsub(/["\r\n]/, "", v); gsub(/\t/, " ", v)
					if (k == "query") q = v
					else if (k == "country") cy = v
					else if (k == "regionName") rg = v
					else if (k == "isp") isp = v
					else if (k == "as") asn = v
				}
				if (q != "") printf "%s\t%s\t%s\t%s\t%s\t%d\n", q, cy, rg, isp, asn, now
			}
		}' >> "$DIR/geo.tsv"
	awk -F'\t' '{ a[$1] = $0 } END { for (k in a) print a[k] }' "$DIR/geo.tsv" > "$DIR/geo.tmp" && mv "$DIR/geo.tmp" "$DIR/geo.tsv"
}

# 概览 JSON（页面头部）
build_state() {
	now=$1; wan=$2
	stats=$(awk -v MAPDIR="$DIR" -v now="$now" "$(cat "$LIB")"'
		{
			tot++
			if ($4 == "tcp") { tcp++; st[$2] = 1 } else { udp++; su[$2] = 1 }
			src[$2] = 1
			if ($1 >= now - 86400 && cls($3, $4, $6) == "L") w24++
		}
		END { printf "%d %d %d %d %d %d %d", tot, tcp, udp, length(src), length(st), length(su), w24 }
	' "$DIR/conn.log")
	[ -z "$stats" ] && stats="0 0 0 0 0 0 0"
	set -- $stats
	tot=$1; tcp24=$2; udp24=$3; src24=$4; srctcp=$5; srcudp=$6; w24=$7

	first=$(head -n 1 "$DIR/conn.log" 2>/dev/null | awk '{ print $1 }')
	[ -z "$first" ] && first=$now
	span=$(( (now - first) / 60 ))
	capped=0
	[ "$tot" -ge "$CONN_KEEP" ] && capped=1
	active=$(awk '{ s += $2 } END { print s + 0 }' "$DIR/active.txt" 2>/dev/null)
	alerts24=$(awk -F'|' -v n="$now" -v ex="$(cat "$DIR/exposed.txt" 2>/dev/null)" '
		BEGIN { m = split(ex, e, " "); for (i = 1; i <= m; i++) EX[e[i]] = 1 }
		$1 + 0 >= n - 86400 {
			if ($2 == "HIGH_RATE") {
				hit = 0; m = split($5, p, ",")
				for (i = 1; i <= m; i++) if (p[i] in EX) { hit = 1; break }
				if (!hit) next
			}
			c++
		}
		END { print c + 0 }' "$ALERTS")
	supp=$(awk -F'\t' -v sc="$SCAN_CONNS" '$6 >= sc && $11 == 0 { n++ } END { print n + 0 }' "$DIR/ips.tsv" 2>/dev/null)

	printf '{"ts":%s,"human":"%s","wan":"%s","uptime":%s,"interval":%s,"exposed":"%s","stats":{"conn24":%d,"ips24":%d,"conn60":0,"active":%d,"alerts24":%d,"udpsrc":%d,"total24":%d,"tcp24":%d,"udp24":%d,"src24":%d,"srctcp":%d,"srcudp":%d,"watch24":%d,"span_m":%d,"capped":%d,"suppressed":%d}}' \
		"$now" "$(date -d "@$now" +'%Y-%m-%d %H:%M:%S')" "$wan" "$(cut -d. -f1 /proc/uptime)" "$INTERVAL" \
		"$(cat "$DIR/exposed.txt" 2>/dev/null)" \
		"$tcp24" "$srctcp" "$active" "$alerts24" "$srcudp" \
		"$tot" "$tcp24" "$udp24" "$src24" "$srctcp" "$srcudp" "$w24" "$span" "$capped" "$supp" \
		> "$DIR/state.json.tmp" && mv "$DIR/state.json.tmp" "$DIR/state.json"
}

# 重启后若当天已有落盘汇总且内存明细为空，用它做基线
TODAY=$(date +%F)
if [ ! -s "$DIR/day.log" ] && [ -s "$DAILY/$TODAY.tsv" ]; then
	cp "$DAILY/$TODAY.tsv" "$DIR/baseline.tsv"
else
	: > "$DIR/baseline.tsv"
fi

last_min=0
last_hour=0
last_geo=0
cur_day=$TODAY
sync_ports
sync_hosts
sync_upnp

while :; do
	now=$(date +%s)
	day=$(date +%F)
	wan=$(ip -4 addr show "$WANIF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)

	if [ "$day" != "$cur_day" ]; then
		write_daily "$cur_day"
		: > "$DIR/day.log"
		: > "$DIR/baseline.tsv"
		cur_day=$day
	fi

	if [ -n "$wan" ]; then
		# 原始方向 + 回复方向 src（DNAT 后的真实落点）；UNREPLIED 用 "-" 占位
		awk -v wan="$wan" '
			{ src=""; dst=""; sp=""; dp=""; rsrc=""; nsrc=0; pr=$3
			  for (i=1; i<=NF; i++) {
			    if ($i ~ /^src=/) {
			      nsrc++; split($i,a,"=")
			      if (nsrc==1) { if (src=="") src=a[2] }
			      else if (nsrc==2 && rsrc=="") rsrc=a[2]
			    }
			    else if (dst=="" && $i ~ /^dst=/)   { split($i,b,"="); dst=b[2] }
			    else if (sp==""  && $i ~ /^sport=/) { split($i,c,"="); sp=c[2] }
			    else if (dp==""  && $i ~ /^dport=/) { split($i,d,"="); dp=d[2] }
			  }
			  if (dst==wan && src!="" && dp!="") print src, sp, dp, pr, (rsrc==""?"-":rsrc)
			}' "$CTFILE" 2>/dev/null \
		| awk '$1 !~ /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/' > "$DIR/ext.txt"

		awk -v now="$now" -v exposed="$(cat "$DIR/exposed.txt")" '
			BEGIN { n = split(exposed, e, " "); for (i = 1; i <= n; i++) ex[e[i]] = 1 }
			FILENAME == ARGV[1] { seen[$2] = 1; next }
			{ k = $1 "|" $2 "|" $3; if (!(k in seen)) printf "%d %s %s %s %s %d %s\n", now, $1, $2, $3, $4, ($3 in ex), $5 }
		' "$DIR/seen.ts" "$DIR/ext.txt" > "$DIR/new.txt"

		if [ -s "$DIR/new.txt" ]; then
			awk '{ print $1, $2, $4, $5, $6, $7 }' "$DIR/new.txt" >> "$DIR/conn.log"
			awk '{ print $1, $2, $4, $5, $6, $7 }' "$DIR/new.txt" >> "$DIR/day.log"
			awk '{ print $1, $2 "|" $3 "|" $4 }' "$DIR/new.txt" >> "$DIR/seen.ts"
		fi

		awk '$4 == "tcp" { c[$1]++ } END { for (i in c) printf "%s\t%d\n", i, c[i] }' "$DIR/ext.txt" > "$DIR/active.txt"
	fi

	if [ $((now - last_min)) -ge 60 ]; then
		last_min=$now
		sync_hosts
		sync_upnp

		awk -v cut=$((now - 900)) '$1 >= cut' "$DIR/seen.ts" > "$DIR/seen.tmp" && mv "$DIR/seen.tmp" "$DIR/seen.ts"
		awk -v cut=$((now - 86400)) '$1 >= cut' "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"
		tail -n "$CONN_KEEP" "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"
		tail -n 50000 "$DIR/day.log" > "$DIR/day.tmp" && mv "$DIR/day.tmp" "$DIR/day.log"

		aggregate "$DIR/conn.log" "$now" "$wan" | awk -F'\t' '{ printf "%012d\t%s\n", $2, $0 }' | sort -k1 -nr | cut -f2- > "$DIR/ips.tsv.tmp" && mv "$DIR/ips.tsv.tmp" "$DIR/ips.tsv"
		aggregate "$DIR/day.log" "$now" "$wan" | awk -F'\t' '{ printf "%012d\t%s\n", $2, $0 }' | sort -k1 -nr | cut -f2- > "$DIR/today.tsv.tmp" && mv "$DIR/today.tsv.tmp" "$DIR/today.tsv"
		aggregate_ports "$now" "$wan"

		: > "$DIR/cand.txt"
		awk -F'\t' -v sp="$SCAN_PORTS" -v sc="$SCAN_CONNS" '
			$14 >= sp { printf "PORT_SCAN\t%s\t%d\t%s\n", $1, $14, $17 }
			$13 >= sc { printf "HIGH_RATE\t%s\t%d\t%s\n", $1, $13, $18 }
		' "$DIR/ips.tsv" >> "$DIR/cand.txt"

		if [ -s "$DIR/cand.txt" ]; then
			awk -v now="$now" '
				FILENAME == ARGV[1] { last[$1] = $2; next }
				{ k = $1 "|" $2; if (!(k in last) || now - last[k] >= 600) print }
			' "$DIR/alerted" "$DIR/cand.txt" > "$DIR/alerts.new"

			if [ -s "$DIR/alerts.new" ]; then
				while IFS="$TAB" read -r type ip cnt ports; do
					ts=$(date -d "@$now" +"%Y-%m-%d %H:%M:%S")
					case "$type" in
						PORT_SCAN) note="60 秒内命中 $cnt 个公网/UPnP 端口：$ports" ;;
						HIGH_RATE) note="60 秒内 $cnt 次连接公网端口：$ports" ;;
						*)         note="" ;;
					esac
					echo "$ts | $type | $ip | 连接 $cnt | $note" >> "$ALERTLOG"
					echo "$now|$type|$ip|$cnt|$ports" >> "$ALERTS"
				done < "$DIR/alerts.new"
				awk -v now="$now" '{ print $1 "|" $2, now }' "$DIR/cand.txt" >> "$DIR/alerted"
			fi
		fi
		awk -v cut=$((now - 900)) '$1 >= cut' "$DIR/alerted" > "$DIR/alerted.tmp" && mv "$DIR/alerted.tmp" "$DIR/alerted"
		tail -n "$ALERT_KEEP" "$ALERTS" > "$ALERTS.tmp" && mv "$ALERTS.tmp" "$ALERTS"
		tail -n "$ALERT_KEEP" "$ALERTLOG" > "$ALERTLOG.tmp" && mv "$ALERTLOG.tmp" "$ALERTLOG"

		if [ $((now - last_hour)) -ge "$HOURLY" ]; then
			last_hour=$now
			sync_ports
			write_daily "$day"
		fi

		if [ $((now - last_geo)) -ge 3600 ]; then
			last_geo=$now
			geo_refresh
		fi

		build_state "$now" "$wan"
	fi

	sleep "$INTERVAL"
done
