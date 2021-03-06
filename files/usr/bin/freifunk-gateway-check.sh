#!/bin/bash
#usage: gateway-check.sh 

ip_rule_priority=98
ip_rule_priority_unreachable=99
DEBUG=false
LOGGER_TAG="GW_CHECK"

setup_gateway_table ()
{
	dev=$1
	via=$2
	gateway_table=$3

	#check if changed
	unset d
	unset v
	eval $(ip ro lis ta $gateway_table | awk ' /default/ {print "d="$5";v="$3} ')
	echo "old: dev=$d, via=$v"
	if [ "$dev" = "$d" -a "$via" = "$v" ]; then
		return
	fi

	#clear table	
	ip route flush table $gateway_table 2>/dev/null

	#redirect gateway ip directly to gateway interface
	ip route add $via/32 dev $dev table $gateway_table 2>/dev/null
	
	#jump over freifunk ranges
	ip route add throw 10.0.0.0/8 table $gateway_table 2>/dev/null
	ip route add throw 172.16.0.0/12 table $gateway_table 2>/dev/null

	#jump over private ranges
	ip route add throw 192.168.0.0/16 table $gateway_table 2>/dev/null

	#add default route (which has wider range than throw, so it is processed after throw)
	ip route add default via $via dev $dev table $gateway_table  
}

#kill running instance
mypid=$$
pname=${0##*/}
IFS=' '
echo	$pname,$mypid
for i in $(pidof $pname)
do
  test "$i" != "$mypid" && echo kill $i && kill -9 $i
done

$DEBUG && echo "start"

#dont use vpn server (or any openvpn server), it could interrupt connection
ping_hosts="8.8.8.8 88.198.196.6 84.38.79.202 204.79.197.200"
#process max 3 user ping
#cfg_ping="$(uci -q get ddmesh.network.gateway_check_ping)"
#gw_ping="$(echo "$cfg_ping" | sed 's#[ ,;/	]\+# #g' | cut -d' ' -f1-3 ) $ping_hosts"
gw_ping="$ping_hosts"
$DEBUG && echo "hosts:[$gw_ping]"

#determine all possible gateways

#icvpn gateways; prefere 
default_icvpn_ifname=icvpn
prefer_icvpn_hosts="10.207.0.130:$default_icvpn_ifname 10.207.0.131:$default_icvpn_ifname"
icvpn_default_route="$prefer_icvpn_hosts $(for i in $(ip ro lis ta zebra | cut -d' ' -f3|sort -u);do echo -n $i:$default_icvpn_ifname' '; done)"
echo "WAN:$default_wan_ifname via preferred hosts: $prefer_icvpn_hosts"


default_lan_ifname=$(nvram get ifname)
default_lan_gateway=$(ip route list table main | sed -n "/default via [0-9.]\+ dev $default_lan_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
if [ -n "$default_lan_gateway" -a -n "$default_lan_ifname" ]; then
	lan_default_route="$default_lan_gateway:$default_lan_ifname"
fi

echo "LAN:$default_lan_ifname via $default_lan_gateway"


_ifname=vpn
default_vpn_ifname=$(ip route list table gateway_pool| sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*dev \([^ 	]\+\).*#\1#p}")
default_vpn_gateway=$(ip route list table gateway_pool| sed -n "/default via [0-9.]\+ dev $_ifname/{s#.*via \([0-9.]\+\).*#\1#p}")
if [ -n "$default_vpn_gateway" -a -n "$default_vpn_ifname" ]; then
	vpn_default_route="$default_vpn_gateway:$default_vpn_ifname"
fi
echo "VPN:$default_vpn_ifname via $default_vpn_gateway"

#try each gateway
ok=false
IFS=' '
#start with vpn, because this is prefered gateway, then WAN and lates LAN
#(there is no forwarding to lan allowed by firewall)
#for g in $vpn_default_route $icvpn_default_route $lan_default_route
for g in $vpn_default_route $lan_default_route 
do
	echo "==========="
	echo "try: $g"
	dev=${g#*:}
	via=${g%:*}
 
	$DEBUG && echo "via=$via, dev=$dev"


	#add ping rule before all others;only pings from this host (no forwards) 
	ip rule del iif lo priority $ip_rule_priority table ping 2>/dev/null
	ip rule add iif lo priority $ip_rule_priority table ping
	ip rule del iif lo priority $ip_rule_priority_unreachable table ping_unreachable 2>/dev/null
	ip rule add iif lo priority $ip_rule_priority_unreachable table ping_unreachable

	#no check of gateway, it might not return icmp reply, also
	#it might not be reachable because of routing rules 
		
	#add ping hosts to special ping table
	ip route flush table ping
	ip route flush table ping_unreachable

	#add route to gateway, to avoid routing via freifunk
	ip route add $via/32 dev $dev table ping

	IFS=' '
	for ip in $gw_ping
	do
		$DEBUG && echo "add ping route ip:$ip"
		ip route add $ip via $via dev $dev table ping
		ip route add unreachable $ip table ping_unreachable
		$DEBUG && echo "route:$(ip route get $ip)"
		$DEBUG && echo "route via:$(ip route get $via)"
	done

	$DEBUG && ip ro li ta ping
	
	#activate routes
	ip route flush cache

	#run check
	ok=false
	IFS=' '
	for ip in $gw_ping
	do
		$DEBUG && echo "ping to: $ip"
		ping -c 2 -w 10 $ip  2>&1 && ok=true && break
	done
	if $ok; then
		$DEBUG && echo "gateway found: via $via dev $dev (landev:$default_lan_ifname, wandev=$default_wan_ifname)"

		#VSERVER: we have found a gateway (either via eth0 or openvpn) -> offer gateway service
		#VSERVER: keep local_gateway untouched. it is setup by S40network (not detected)
		#VSERVER: but it needs to be re-checkt. because if network is down, default route is removed from routing table and 
		#VSERVER: must be readded
		#VSERVER:  - it ensures that host has always a working gateway. 

		#always add wan or lan to local gateway
		if [ "$dev" = "$default_lan_ifname" -o "$dev" = "$default_wan_ifname" ]; then	
			logger -ts "$LOGGER_TAG" "Set local gateway: dev:$dev, ip:$via"
			setup_gateway_table $dev $via local_gateway
		fi

		# Add any gateway to public table if internet was enabled.
		# If internet is disabled, add only vpn if detected.
		# When lan/wan gateway gets lost, also vpn get lost
		# If only vpn get lost, remove public gateway
		if [ "$(nvram get ddmesh_disable_gateway)" = "0" -a "$dev" = "$default_vpn_ifname" ]; then
			logger -ts "$LOGGER_TAG" "Set public gateway: dev:$dev, ip:$via"
			setup_gateway_table $dev $via public_gateway
			/etc/init.d/S52batmand gateway
		else
			logger -ts "$LOGGER_TAG" "Clear public gateway."
			ok=false
		fi
		
		break;
	fi

done
unset IFS

ip route flush table ping
ip route flush table ping_unreachable
ip rule del iif lo priority $ip_rule_priority table ping >/dev/null
ip rule del iif lo priority $ip_rule_priority_unreachable table ping_unreachable >/dev/null

if ! $ok; then
	$DEBUG && echo "no gateway"
	#remove all in default route from public_gateway table
	ip route flush table public_gateway 2>/dev/null
	/etc/init.d/S52batmand no_gateway

	# try to restart openvpn, in case connection is dead, but active ($ok was true)
	# also if no vpn was active ($ok was false)
	/etc/init.d/openvpn restart
fi

$DEBUG && echo "end."
exit 0
