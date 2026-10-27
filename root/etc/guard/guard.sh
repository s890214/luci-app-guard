#!/bin/sh
# luci-app-guard 采集守护（只记录，不封禁）
# 数据源：/proc/net/nf_conntrack（只取原始方向 dst=WAN 的入站连接）
# 对外端口：从 nft 同步（lucky666.cn_auto + dstnat_wan），仅用于标注，不参与拦截
# 留存：连接明细 24h（内存）；按天汇总落盘保留 retain_days 天；告警落盘保留 alert_keep 条

DIR=${GUARD_DIR:-/tmp/guard}
DATA=${GUARD_DATA:-/etc/guard}
ALERTLOG=$DATA/alerts.log
ALERTS=$DATA/alerts.tsv
DAILY=$DATA/daily
CTFILE=${GUARD_CONNTRACK:-/proc/net/nf_conntrack}
WANIF=${GUARD_WANIF:-pppoe-wan}

cfg() { v=$(uci -q get "guard.main.$1" 2>/dev/null); [ -z "$v" ] && v=$2; echo "$v"; }
INTERVAL=${GUARD_INTERVAL:-$(cfg interval 10)}
SCAN_PORTS=$(cfg scan_ports 5)
SCAN_CONNS=$(cfg scan_conns 30)
RETAIN_DAYS=$(cfg retain_days 30)
ALERT_KEEP=$(cfg alert_keep 5000)
HOURLY=${GUARD_HOURLY:-3600}
[ "$(cfg enabled 1)" = "0" ] && exit 0

mkdir -p "$DIR" "$DATA" "$DAILY"
touch "$DIR/conn.log" "$DIR/day.log" "$DIR/seen.ts" "$DIR/alerted" "$DIR/alerts.tsv" "$ALERTS" "$ALERTLOG"

# 按 IP 聚合：输出 ip total first last ports c60 p60 portlist tcp udp
aggregate() {
	awk -v now="$2" '
		{ t=$1; ip=$2; dp=$3; pr=$4
		  if (t >= now-86400) {
		    total[ip]++
		    if (pr=="tcp") tcp[ip]++; else udp[ip]++
		    if (!(ip in first) || t < first[ip]) first[ip]=t
		    if (t > last[ip]) last[ip]=t
		    ports[ip"|"dp]=1
		  }
		  if (t >= now-60) { c60[ip]++; p60[ip"|"dp]=1 }
		}
		END {
		  for (k in ports) { split(k,a,"|"); ip=a[1]; if (pc[ip] < 12) plall[ip]=plall[ip] (plall[ip]==""?"":",") a[2]; pc[ip]++ }
		  for (k in p60)   { split(k,a,"|"); pc60[a[1]]++; pl[a[1]]=pl[a[1]] (pl[a[1]]==""?"":",") a[2] }
		  for (ip in total) {
		    pl=plall[ip]; if (pc[ip] > 12) pl=pl",+"(pc[ip]-12)
		    printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\n", ip, total[ip], first[ip], last[ip], pc[ip]+0, c60[ip]+0, pc60[ip]+0, pl, tcp[ip]+0, udp[ip]+0
		  }
		}' "$1"
}

# 落盘当天汇总：基线(重启前) + 今日实时，按 IP 合并
write_daily() {
	[ -s "$DIR/today.tsv" ] || return 0
	awk -F'\t' '
		FILENAME==ARGV[1] { b[$1]=$0; next }
		{
		  ip=$1
		  if (ip in b) {
		    split(b[ip],x,"\t")
		    tcp=$9+x[9]; udp=$10+x[10]; ports=$5+x[5]
		    pl=$8; n=split(x[8],xp,","); for(i=1;i<=n;i++) if (index(","pl",", "," xp[i] ",")==0) pl=pl (pl==""?"":",") xp[i]
		    first=(x[3]+0<first+0||first==0)?x[3]:first
		    last=(x[4]+0>last+0)?x[4]:last
		  } else { tcp=$9; udp=$10; ports=$5; pl=$8; first=$3; last=$4 }
		  printf "%s\t%d\t%d\t%d\t%s\t%d\t%d\n", ip, tcp, udp, ports, pl, first, last
		}' "$DIR/baseline.tsv" "$DIR/today.tsv" > "$DAILY/$1.tsv.tmp" && mv "$DAILY/$1.tsv.tmp" "$DAILY/$1.tsv"
	find "$DAILY" -name '*.tsv' -mtime +"$RETAIN_DAYS" -delete 2>/dev/null
}

# 概览 JSON（页面头部）
build_state() {
	now=$1; wan=$2
	printf '{"ts":%s,"human":"%s","wan":"%s","uptime":%s,"interval":%s,"exposed":"%s","stats":{"conn24":%s,"ips24":%s,"conn60":%s,"active":%s,"alerts24":%s,"udpsrc":%s}}' \
		"$now" "$(date -d "@$now" +'%Y-%m-%d %H:%M:%S')" "$wan" "$(cut -d. -f1 /proc/uptime)" "$INTERVAL" \
		"$(cat "$DIR/exposed.txt" 2>/dev/null)" \
		"$(awk '$4=="tcp"' "$DIR/conn.log" | wc -l)" \
		"$(awk '$4=="tcp" {print $2}' "$DIR/conn.log" | sort -u | wc -l)" \
		"$(awk -v n="$now" '$1>=n-60 && $4=="tcp"' "$DIR/conn.log" | wc -l)" \
		"$(awk '{s+=$2} END{print s+0}' "$DIR/active.txt" 2>/dev/null)" \
		"$(awk -F'|' -v n="$now" '$1>=n-86400' "$ALERTS" | wc -l)" \
		"$(awk '$4=="udp" {print $2}' "$DIR/conn.log" | sort -u | wc -l)" \
		> "$DIR/state.json.tmp" && mv "$DIR/state.json.tmp" "$DIR/state.json"
}

sync_ports() {
	{
		nft list chain inet fw4 lucky666.cn_auto 2>/dev/null | awk '/dport [0-9]+ accept/ {for(i=1;i<=NF;i++) if($i=="dport") print $(i+1)}'
		nft list chain inet fw4 dstnat_wan 2>/dev/null | awk '/dnat/ {for(i=1;i<=NF;i++) if($i=="dport") print $(i+1)}'
	} | sort -un | tr '\n' ' ' > "$DIR/exposed.txt"
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
cur_day=$TODAY
sync_ports

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
		# 取原始方向(src/dst/sport/dport) + 回复方向的 src，即 DNAT 之后的真实落点。
		# 落在路由器自己身上时它等于 LAN 地址；转发到内网设备时就是那台设备的 IP。
		# UNREPLIED 的连接没有回复方向，用 "-" 占位。
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
			BEGIN { n=split(exposed,e," "); for (i=1;i<=n;i++) ex[e[i]]=1 }
			FILENAME==ARGV[1] { seen[$2]=1; next }
			{ k=$1"|"$2"|"$3; if (!(k in seen)) printf "%d %s %s %s %s %d %s\n", now, $1, $2, $3, $4, ($3 in ex), $5 }
		' "$DIR/seen.ts" "$DIR/ext.txt" > "$DIR/new.txt"

		if [ -s "$DIR/new.txt" ]; then
			awk '{print $1, $2, $4, $5, $6, $7}' "$DIR/new.txt" >> "$DIR/conn.log"
			awk '{print $1, $2, $4, $5, $6, $7}' "$DIR/new.txt" >> "$DIR/day.log"
			awk '{print $1, $2"|"$3"|"$4}' "$DIR/new.txt" >> "$DIR/seen.ts"
		fi

		awk '$4=="tcp" {c[$1]++} END {for (i in c) printf "%s\t%d\n", i, c[i]}' "$DIR/ext.txt" > "$DIR/active.txt"
	fi

	if [ $((now - last_min)) -ge 60 ]; then
		last_min=$now

		awk -v cut=$((now-900)) '$1>=cut' "$DIR/seen.ts" > "$DIR/seen.tmp" && mv "$DIR/seen.tmp" "$DIR/seen.ts"
		awk -v cut=$((now-86400)) '$1>=cut' "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"
		tail -n 20000 "$DIR/conn.log" > "$DIR/conn.tmp" && mv "$DIR/conn.tmp" "$DIR/conn.log"
		tail -n 50000 "$DIR/day.log" > "$DIR/day.tmp" && mv "$DIR/day.tmp" "$DIR/day.log"

		aggregate "$DIR/conn.log" "$now" > "$DIR/ips.tsv"
		aggregate "$DIR/day.log" "$now" > "$DIR/today.tsv"

		: > "$DIR/cand.txt"
		awk -F'\t' -v sp="$SCAN_PORTS" -v sc="$SCAN_CONNS" '
			$7 >= sp { printf "PORT_SCAN\t%s\t%d\t%s\n", $1, $7, $8 }
			$6 >= sc { printf "HIGH_RATE\t%s\t%d\t%s\n", $1, $6, $8 }
		' "$DIR/ips.tsv" >> "$DIR/cand.txt"

		if [ -s "$DIR/cand.txt" ]; then
			awk -v now="$now" '
				FILENAME==ARGV[1] { last[$1]=$2; next }
				{ k=$1"|"$2; if (!(k in last) || now-last[k] >= 600) print }
			' "$DIR/alerted" "$DIR/cand.txt" > "$DIR/alerts.new"

			if [ -s "$DIR/alerts.new" ]; then
				while IFS="$(printf '\t')" read -r type ip cnt ports; do
					ts=$(date -d "@$now" +"%Y-%m-%d %H:%M:%S")
					case "$type" in
						PORT_SCAN) note="60 秒内命中 $cnt 个不同端口：$ports" ;;
						HIGH_RATE) note="60 秒内 $cnt 次连接" ;;
						*)         note="" ;;
					esac
					echo "$ts | $type | $ip | 连接 $cnt | $note" >> "$ALERTLOG"
					echo "$now|$type|$ip|$cnt|$ports" >> "$ALERTS"
				done < "$DIR/alerts.new"
				awk -v now="$now" '{print $1"|"$2, now}' "$DIR/cand.txt" >> "$DIR/alerted"
			fi
		fi
		awk -v cut=$((now-900)) '$1>=cut' "$DIR/alerted" > "$DIR/alerted.tmp" && mv "$DIR/alerted.tmp" "$DIR/alerted"
		tail -n "$ALERT_KEEP" "$ALERTS" > "$ALERTS.tmp" && mv "$ALERTS.tmp" "$ALERTS"
		tail -n "$ALERT_KEEP" "$ALERTLOG" > "$ALERTLOG.tmp" && mv "$ALERTLOG.tmp" "$ALERTLOG"

		if [ $((now - last_hour)) -ge "$HOURLY" ]; then
			last_hour=$now
			write_daily "$day"
		fi

		build_state "$now" "$wan"
	fi

	sleep "$INTERVAL"
done
