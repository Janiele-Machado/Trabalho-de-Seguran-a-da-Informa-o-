#!/bin/sh
set -e
echo "[fw] habilitando encaminhamento de pacotes..."
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
echo "[fw] carregando regras de /etc/firewall/firewall.sh ..."
sh /etc/firewall/firewall.sh
touch /tmp/firewall.ready
echo "[fw] firewall ativo."
exec tail -f /dev/null
