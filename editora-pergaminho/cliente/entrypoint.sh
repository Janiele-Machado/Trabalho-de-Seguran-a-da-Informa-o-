#!/bin/sh
# Instala as rotas para as demais redes via firewall (equivale ao que o DHCP faria).
: "${FW_GW:?defina FW_GW}"
for NET in $ROTAS; do
  ip route replace "$NET" via "$FW_GW"
done
echo "[cliente] rotas:"; ip route
exec sleep infinity
