#!/bin/sh

echo 'Content-type: text/plain txt'
echo ''

BMXD_DB_PATH=/var/lib/freifunk/bmxd
ddmesh_node=$(nvram get ddmesh_node)
test -z "$ddmesh_node" && exit

eval $(ddmesh-ipcalc.sh -n $ddmesh_node)
eval $(sudo /usr/bin/freifunk-gateway-info.sh)

WLDEV=$(l=$(grep : /proc/net/wireless);l=${l%:*};echo ${l##* })

cat << EOM
{
 "version":"4",
 "timestamp":"$(date +'%s')",
 "data":{

EOM

#node info
cat << EOM
		"firmware":{
			"version":"",
			"DISTRIB_ID":"",
			"DISTRIB_RELEASE":"",
			"DISTRIB_REVISION":"",
			"DISTRIB_CODENAME":"",
			"DISTRIB_TARGET":"",
			"DISTRIB_DESCRIPTION":""
		},
		"system":{
			"uptime":"$(uptime)",
			"uname":"$(uname -a)",
			"nameserver": [
$(cat /var/etc/resolv.conf.dynamic | sed -n '/nameserver[ 	]\+10\.200/{s#[ 	]*nameserver[ 	]*\(.*\)#\t\t\t\t"\1",#;p}' | sed '$s#,##')
			],
			"date":"$(date)",
			"board":"",
			"model":"",
			"model2":"",
			"cpuinfo":"$(cat /proc/cpuinfo | sed -n '/system type/s#.*:[ 	]*##p')",
			"bmxd" : "$(cat $BMXD_DB_PATH/status)"
		},
		"common":{
			"city":"$(nvram get city)",
			"node":"$_ddmesh_node",
			"domain":"$_ddmesh_domain",
			"ip":"$_ddmesh_ip"
		},
		"gps":{
			"latitude":"$(nvram get gps_latitude)",
			"longitude":"$(nvram get gps_longitude)",
			"altitude":"$(nvram get gps_altitude)"
		},
		"contact":{
			"name":"$(nvram get contact_name)",
			"location":"$(nvram get contact_location)",
			"email":"$(nvram get contact_email)",
			"note":"$(nvram get contact_note)"
		},
EOM

cat<<EOM
		"statistic" : {
			"accepted_user_count" : "0",
			"dhcp_count" : "0",
			"dhcp_lease" : "0",
			"traffic_adhoc": "",
			"traffic_ap": "",
			"traffic_ovpn": "$(ifconfig vpn0 | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
			"traffic_icvpn": "$(ifconfig icvpn | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')",
EOM
			for iface in $(ip link show | sed -n '/^[0-9]\+:/s#^[0-9]\+:[ ]\+\(.*\):.*$#\1#p' | sed "/vpn/d;/lo/d;/bat/d")
			do
				echo "			\"traffic_$iface\": \"$(ifconfig $iface | sed -n '/RX bytes/{s#[ ]*RX bytes:\([0-9]\+\)[^:]\+:\([0-9]\+\).*#\1,\2#;p}')\","
			done
cat<<EOM
$(cat /proc/meminfo | sed 's#\(.*\):[ 	]\+\([0-9]\+\)[ 	]*\(.*\)#\t\t\t\"meminfo_\1\" : \"\2\ \3\",#')
			"cpu_load" : "$(cat /proc/loadavg)",
			"cpu_stat" : "$(cat /proc/stat | sed -n '/^cpu[ 	]\+/{s# \+# #;p}')",
			"gateway_usage" : [
$(cat /var/statistic/gateway_usage | sed 's#\([^:]*\):\(.*\)#\t\t\t\t{"\1":"\2"},#' | sed '$s#,[ 	]*$##') ]
		},
EOM

#bmxd
#$(ip route list table bat_route | sed 's#\(.*\)#			"\1",#; $s#,[ 	]*$##') ],
cat<<EOM
		"bmxd":{
			"routing_tables":{
				"route":{
					"link":[
$(ip route list table bat_route | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t\t\t{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  			"global":[
$(ip route list table bat_route | sed  '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t\t\t{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
	  		},
			"hna":{
				"link":[
$(ip route list table bat_hna | sed -n '/scope[ ]\+link/{s#^\([0-9./]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t{"target":"\1","interface":"\2"},#;p}' | sed '$s#,[ 	]*$##') ],
		  		"global":[
$(ip route list table bat_hna | sed -n '/scope[ ]\+link/d;s#^\([0-9./]\+\)[	 ]\+via[	 ]\+\([0-9.]\+\)[	 ]\+dev[	 ]\+\([^	 ]\+\).*#\t\t\t\t{"target":"\1","via":"\2","interface":"\3"},#p' | sed '$s#,[ 	]*$##') ]
				}
			},
			"gateways":{
				"selected":"$(cat $BMXD_DB_PATH/gateways | sed -n 's#^[	 ]*=>[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"preferred":"$(cat $BMXD_DB_PATH/gateways | sed -n '1,1s#^.*preferred gateway:[	 ]\+\([0-9.]\+\).*$#\1#p')",
				"gateways":[
$(cat $BMXD_DB_PATH/gateways | sed -n '
				/^[	 ]*$/d
				1,1d
				s#^[	 =>]*\([0-9.]\+\).*$#\t\t\t\t{"ip":"\1"},#p
				' | sed '$s#,[	 ]*$##') ]
			},
			"info":[
$(cat $BMXD_DB_PATH/info | sed 's#^[ 	]*\(.*\)$#\t\t\t\t"\1",#; $s#,[ 	]*$##') ]
		},
  		"internet_tunnel":{
			"ipv4_address":"$iptest_address4",
			"ipv4_country":"$iptest_country4",
			"ipv4_country_code":"$iptest_country_code4",
			"ipv4_imgurl":"$iptest_imgurl4",
			"ipv6_address":"$iptest_address6",
			"ipv6_country":"$iptest_country6",
			"ipv6_country_code":"$iptest_country_code6",
			"ipv6_imgurl":"$iptest_imgurl6"
		},
		"connections":[
EOM
netstat -tn 2>/dev/null | grep ESTABLISHED | awk '
	{
		split($4,a,":");
		split($5,b,":");
		if(match(a[1],"169.254")) a[1]=ENVIRON["_ddmesh_ip"]
		#allow display node ip
		if(a[1] == ENVIRON["_ddmesh_ip"])
		{
			printf("\t\t\t{\"local\":{\"ip\":\"%s\",\"port\":\"%s\"},\"foreign\":{\"ip\":\"%s\",\"port\":\"%s\"}},\n",a[1],a[2],b[1],b[2]);
		}
	}' | sed '$s#,[ 	]*$##'
cat << EOM
		]
EOM

# remove last comma
#$s#,[ 	]*$##

cat << EOM
  }
}
EOM
