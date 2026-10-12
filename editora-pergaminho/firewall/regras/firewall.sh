#!/bin/sh
# ============================================================
#  Firewall da Editora Pergaminho
#  Politica padrao: DROP em INPUT, FORWARD e OUTPUT.
#  Recarregar sem reiniciar:
#    docker compose exec firewall sh /etc/firewall/firewall.sh
# ============================================================
set -eu

IPT=iptables
$IPT -S >/dev/null 2>&1 || IPT=iptables-legacy

# ---- Sub-redes e hosts ----
EDITORES="10.88.10.0/24"
AUTORES="10.88.40.0/24"
DMZ_WEB="10.88.20.0/24"
DMZ_DADOS="10.88.30.0/24"
PORTAL="10.88.20.10"
API="10.88.20.20"
DB="10.88.30.10"
COFRE="10.88.30.20"

# ---- Descobre a interface de cada rede pelo prefixo de IP ----
iface() { ip -o -4 addr show | awk -v p="$1" '$4 ~ ("^" p) {print $2; exit}'; }
IF_ED=$(iface 10.88.10.)
IF_AU=$(iface 10.88.40.)
IF_DW=$(iface 10.88.20.)
IF_DD=$(iface 10.88.30.)
for v in "$IF_ED" "$IF_AU" "$IF_DW" "$IF_DD"; do
  [ -n "$v" ] || { echo "[fw] ERRO: interface nao encontrada"; exit 1; }
done
echo "[fw] interfaces: editores=$IF_ED autores=$IF_AU dmz_web=$IF_DW dmz_dados=$IF_DD"

# ---- Limpa e define politica padrao DROP ----
$IPT -F
$IPT -X
$IPT -P INPUT DROP
$IPT -P FORWARD DROP
$IPT -P OUTPUT DROP
# (nao limpamos a tabela nat inteira: o Docker usa regras nela para o DNS interno)

# ---- Chain auxiliar: registra (com limite) e descarta ----
$IPT -N LOGDROP
$IPT -A LOGDROP -m limit --limit 10/min --limit-burst 20 \
     -j LOG --log-prefix "FW-DROP " --log-level 4 || true
$IPT -A LOGDROP -j DROP

# ================= INPUT (trafego destinado ao proprio firewall) =================
$IPT -A INPUT -i lo -j ACCEPT
$IPT -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
$IPT -A INPUT -i "$IF_ED" -s "$EDITORES" -p icmp --icmp-type echo-request \
     -m limit --limit 5/second -j ACCEPT
$IPT -A INPUT -j LOGDROP

# ================= OUTPUT (trafego gerado pelo firewall) =================
$IPT -A OUTPUT -o lo -j ACCEPT
$IPT -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# demais: DROP pela politica

# ================= FORWARD (trafego entre redes) =================
fw() { $IPT -A FORWARD "$@"; }

# R0 - anti-spoofing: cada interface so aceita o IP da sua propria rede
fw -i "$IF_ED" ! -s "$EDITORES"  -m comment --comment "R0 anti-spoof editores"  -j DROP
fw -i "$IF_AU" ! -s "$AUTORES"   -m comment --comment "R0 anti-spoof autores"   -j DROP
fw -i "$IF_DW" ! -s "$DMZ_WEB"   -m comment --comment "R0 anti-spoof dmz_web"   -j DROP
fw -i "$IF_DD" ! -s "$DMZ_DADOS" -m comment --comment "R0 anti-spoof dmz_dados" -j DROP
fw -m conntrack --ctstate INVALID -m comment --comment "R0 pacotes invalidos" -j DROP

# R11 - respostas de conexoes ja autorizadas
fw -m conntrack --ctstate ESTABLISHED,RELATED -m comment --comment "R11 retorno" -j ACCEPT

# --- Liberacoes explicitas ---
fw -i "$IF_ED" -s "$EDITORES" -d "$PORTAL" -p tcp --dport 80 \
   -m conntrack --ctstate NEW -m comment --comment "R1 editores->portal tcp80" -j ACCEPT
fw -i "$IF_ED" -s "$EDITORES" -d "$API" -p tcp --dport 5000 \
   -m conntrack --ctstate NEW -m comment --comment "R2 editores->api tcp5000" -j ACCEPT
fw -i "$IF_AU" -s "$AUTORES" -d "$PORTAL" -p tcp --dport 80 \
   -m conntrack --ctstate NEW -m comment --comment "R3 autores->portal tcp80" -j ACCEPT
fw -i "$IF_ED" -s "$EDITORES" -d "$DMZ_WEB" -p icmp --icmp-type echo-request \
   -m comment --comment "R4 editores->dmz_web ping" -j ACCEPT

# --- Bloqueios explicitos (com log) ---
fw -i "$IF_ED" -d "$DMZ_DADOS" -m comment --comment "R5 editores->dmz_dados (db/cofre)" -j LOGDROP
fw -i "$IF_AU" -d "$DMZ_DADOS" -m comment --comment "R6 autores->dmz_dados (db/cofre)"  -j LOGDROP
fw -i "$IF_AU" -d "$API"       -m comment --comment "R7 autores->api direta"            -j LOGDROP
fw -i "$IF_AU" -d "$EDITORES"  -m comment --comment "R8 autores->rede editores"         -j LOGDROP
fw -i "$IF_ED" -d "$AUTORES"   -m comment --comment "R9 editores->rede autores"         -j LOGDROP
for SRC_IF in "$IF_DW" "$IF_DD"; do
  for DST in "$EDITORES" "$AUTORES"; do
    fw -i "$SRC_IF" -d "$DST" -m comment --comment "R10 DMZ->LAN (anti-pivo)" -j LOGDROP
  done
done

# R12 - regra final: tudo o que sobrou e registrado e descartado
fw -m comment --comment "R12 default deny" -j LOGDROP

# ================= NAT =================
# 1) DNAT (publicacao dos servicos no IP do firewall)
#    O cliente conecta no IP do firewall da SUA rede (ex.: 10.88.10.254:80) e o
#    firewall redireciona para o servico real. Depois do DNAT, o pacote passa
#    pela tabela FORWARD, onde a matriz de regras (R1..R12) decide se segue ou nao.
#      porta 80   -> portal-web   (R1/R3 liberam)
#      porta 5000 -> api          (R2 libera para editores; R7 bloqueia autores)
#      porta 5432 -> db           (R5/R6 BLOQUEIAM)
#      porta 8080 -> cofre:80     (R5/R6 BLOQUEIAM)
$IPT -t nat -F PREROUTING
publicar() { $IPT -t nat -A PREROUTING -i "$1" -p tcp --dport "$2" -j DNAT --to-destination "$3"; }
for IFX in "$IF_ED" "$IF_AU"; do
  publicar "$IFX" 80   "$PORTAL:80"
  publicar "$IFX" 5000 "$API:5000"
  publicar "$IFX" 5432 "$DB:5432"
  publicar "$IFX" 8080 "$COFRE:80"
done

# 2) MASQUERADE: as maquinas da DMZ nao tem rota para as redes de clientes; com o
#    MASQUERADE elas respondem diretamente ao firewall (mesmo segmento).
for IFX in "$IF_DW" "$IF_DD"; do
  $IPT -t nat -C POSTROUTING -o "$IFX" -j MASQUERADE 2>/dev/null \
    || $IPT -t nat -A POSTROUTING -o "$IFX" -j MASQUERADE
done

echo "[fw] NAT (PREROUTING):"
$IPT -t nat -L PREROUTING -n
echo "[fw] regras FORWARD carregadas:"
$IPT -L FORWARD -n --line-numbers
