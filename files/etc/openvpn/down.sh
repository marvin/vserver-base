#!/bin/bash
#cmd tun_dev tun_mtu link_mtu ifconfig_local_ip ifconfig_remote_ip
m=${dev#vpn}
ip route del default dev $dev via $route_vpn_gateway table gateway_pool metric $m

iptables -t nat -D POSTROUTING -o vpn+ -j SNAT --to-source $ifconfig_local

#update gateway infos and routing tables, fast after openvpn closes connection
#Run in background, else openvpn blocks
/usr/bin/freifunk-gateway-check.sh&

#tell always "ok" to openvpn;else in case of errors of "ip route..." openvpn exits
exit 0

