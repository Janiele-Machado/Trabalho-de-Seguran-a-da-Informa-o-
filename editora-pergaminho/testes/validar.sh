#!/usr/bin/env bash
# Validacao automatica: testes positivos, negativos e conferencia dos contadores do firewall.
# Uso (na raiz do projeto):  bash testes/validar.sh
set -u
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }
TOKEN="${API_TOKEN:-troque-este-token}"
C="docker compose"

ed()  { $C exec -T estacao-editor "$@"; }
au()  { $C exec -T autor-externo "$@"; }
dmz() { $C exec -T portal-web "$@"; }
fwcnt() {  # pacotes ja contados pela regra $1 (ex.: R5) na chain FORWARD
  $C exec -T firewall sh -c 'iptables -L FORWARD -n -v -x 2>/dev/null || iptables-legacy -L FORWARD -n -v -x' \
    | tr -d '\r' | grep "/\* $1 " | head -1 | awk '{print $1}'
}

ok=0; ko=0
t_ok()  { if eval "$2" >/dev/null 2>&1; then echo "  [PASS] $1"; ok=$((ok+1)); else echo "  [FAIL] $1"; ko=$((ko+1)); fi; }
t_blk() { if eval "$2" >/dev/null 2>&1; then echo "  [FAIL] $1 (NAO foi bloqueado!)"; ko=$((ko+1)); else echo "  [PASS] $1 (bloqueado)"; ok=$((ok+1)); fi; }

for r in R1 R2 R3 R5 R6 R7; do eval "${r}_0=\$(fwcnt $r)"; done

echo "== TESTES POSITIVOS =="
t_ok  "P1 editor -> portal HTTP 80 (via firewall, R1)"   "ed curl -sf -m5 -o /dev/null http://portal-web/"
t_ok  "P2 editor -> /api/health via portal"              "ed curl -sf -m5 http://portal-web/api/health | grep -q ok"
t_ok  "P3 editor -> API :5000 (db/cofre up) (R2)"        "ed curl -sf -m5 http://api-editorial:5000/status | grep -q '\"db\": \"up\"'"
t_ok  "P4 editor le manuscrito via API com token"        "ed curl -sf -m5 -H 'X-API-Token: $TOKEN' http://api-editorial:5000/manuscritos/a-sombra-do-cerrado-cap01.txt | grep -q FLAG"
t_ok  "P5 editor -> ping no firewall"                    "ed ping -c1 -W2 10.88.10.254"
t_ok  "P6 autor -> portal HTTP 80 (R3)"                  "au curl -sf -m5 -o /dev/null http://portal-web/"
t_ok  "P7 autor envia submissao (POST)"                  "au curl -sf -m5 -X POST -H 'Content-Type: application/json' -d '{\"titulo\":\"Meu livro\"}' http://portal-web/api/submissao"

echo; echo "== TESTES NEGATIVOS =="
t_blk "N1 editor -> banco (10.88.10.254:5432)"           "ed nc -z -w3 10.88.10.254 5432"
t_ok  "N2 nmap do editor: 5432 aparece como filtered"    "ed nmap -Pn -p 5432 10.88.10.254 | grep -q filtered"
t_blk "N3 editor -> cofre (10.88.10.254:8080)"           "ed curl -sf -m3 http://10.88.10.254:8080/"
t_blk "N4 autor -> API direta (10.88.40.254:5000)"       "au curl -sf -m3 http://10.88.40.254:5000/status"
t_blk "N5 autor -> banco (10.88.40.254:5432)"            "au nc -z -w3 10.88.40.254 5432"
t_blk "N6 autor -> ping no firewall (so editores podem)" "au ping -c1 -W2 10.88.40.254"
t_blk "N7 autor tenta ler manuscrito pelo portal"        "au curl -sf -m3 http://portal-web/api/manuscritos/a-sombra-do-cerrado-cap01.txt"
t_blk "N8 autor -> /api/status pelo portal (403)"        "au curl -sf -m3 http://portal-web/api/status"
t_ok  "N9 autor: so a porta 80 esta aberta no firewall"  "[ \"\$(au nmap -Pn -p 22,80,443,5000,5432,8080 10.88.40.254 | grep -c ' open ')\" = 1 ]"
t_blk "N10 portal comprometido nao alcanca a LAN"        "dmz wget -T3 -qO- http://10.88.10.10"
t_blk "N11 contorno: editor -> IP interno do banco direto" "ed nc -z -w3 10.88.30.10 5432"

echo; echo "== CONTADORES: as regras realmente atuaram =="
for r in R1 R2 R3 R5 R6 R7; do
  now=$(fwcnt $r); before=$(eval "echo \${${r}_0:-0}")
  t_ok "C-$r contador subiu ($before -> ${now:-?})" "[ \"${now:-0}\" -gt \"$before\" ]"
done

echo; echo "== TABELA COMPLETA (evidencia) =="
$C exec -T firewall sh -c 'iptables -L FORWARD -n -v --line-numbers 2>/dev/null || iptables-legacy -L FORWARD -n -v --line-numbers'

echo; echo "Resultado: $ok passaram, $ko falharam."
[ "$ko" -eq 0 ]
