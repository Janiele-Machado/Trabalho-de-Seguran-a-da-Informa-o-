# Relatório Técnico: Editora Pergaminho

## 1. Definição do Case

A **Editora Pergaminho** (empresa hipotética, inspirada em riscos reais do mercado editorial) publica
literatura nacional e prepara o lançamento de *A Sombra do Cerrado, Livro 3*, com embargo até 15/03/2027.
O ativo mais valioso da empresa são os **manuscritos inéditos**: o vazamento de capítulos antes do lançamento
causa perda de receita, quebra de contrato com o autor e dano de marca.

Serviços que precisam operar:
- **Portal de submissão** para autores e agentes literários enviarem propostas (acesso externo).
- **Painel/API editorial** usado pela equipe interna (editores, revisores).
- **Banco de dados** com autores, contratos, adiantamentos e royalties (dados pessoais e financeiros, LGPD).
- **Cofre de manuscritos**: arquivos dos originais em revisão.

## 2. Diagnóstico: Cenário Atual vs. Proposta

### 2.1 Cenário atual (problemas mapeados)
| # | Problema | Risco |
|---|---|---|
| 1 | Rede plana: estações, portal, banco e arquivos no mesmo segmento | Qualquer máquina comprometida alcança tudo |
| 2 | Banco de contratos acessível por qualquer estação | Vazamento de dados financeiros/pessoais (LGPD) |
| 3 | Pasta de manuscritos exposta sem intermediação | Cópia direta de originais embargados |
| 4 | Portal público no mesmo segmento da rede interna | Invasão do portal permite pivotar para a LAN |
| 5 | Autores externos com visibilidade da rede editorial | Varredura (nmap) e movimentação lateral |
| 6 | Ausência de registro de tentativas bloqueadas | Impossível auditar ou detectar reconhecimento |

### 2.2 Proposta de solução
- **Segmentação em 4 redes** (editores, autores, DMZ web, DMZ dados) ligadas **apenas** por um firewall.
- **DMZ em duas camadas:** o que recebe tráfego externo (portal) fica separado do que guarda dados (db/cofre). Apenas a **API** pertence às duas, como ponte controlada e autenticada (token).
- **Política DROP por padrão** (INPUT/FORWARD/OUTPUT) e liberações mínimas por origem, destino e porta (menor privilégio).
- **Anti-spoofing, bloqueio de pacotes inválidos e rota de retorno apenas para conexões estabelecidas.**
- **Regra anti-pivô:** DMZ nunca inicia conexão para as redes de clientes.
- **Log com limite de taxa** (`FW-DROP`) e contadores por regra para auditoria.
- Nginx expõe somente dois endpoints da API (`/api/health`, `/api/submissao`); o resto retorna 403.

## 3. Matriz de Regras de Segurança (Firewall)

| ID | Origem | Destino | Porta/Protocolo | Ação | Justificativa de negócio |
|---|---|---|---|---|---|
| R0 | Qualquer interface | (IP fora da própria rede) / pacotes inválidos | qualquer | DROP | Anti-spoofing |
| R1 | Rede Editores | Portal (172.20.20.10) | TCP 80 | ACCEPT | Equipe usa o portal editorial |
| R2 | Rede Editores | API (172.20.20.20) | TCP 5000 | ACCEPT | Painel editorial acessa manuscritos autenticados |
| R3 | Rede Autores | Portal (172.20.20.10) | TCP 80 | ACCEPT | Autores enviam propostas |
| R4 | Rede Editores | DMZ Web | ICMP echo-request | ACCEPT | Diagnóstico de rede |
| R5 | Rede Editores | DMZ Dados (db 5432, cofre 80) | qualquer | DROP + LOG | Ninguém acessa banco/cofre direto; só a API |
| R6 | Rede Autores | DMZ Dados | qualquer | DROP + LOG | Externo jamais toca em dados |
| R7 | Rede Autores | API direta | qualquer | DROP + LOG | Autor só passa pelo portal |
| R8 | Rede Autores | Rede Editores | qualquer | DROP + LOG | Impede varredura da rede interna |
| R9 | Rede Editores | Rede Autores | qualquer | DROP + LOG | Sem iniciar conexões para terceiros |
| R10 | DMZ Web / DMZ Dados | Redes Editores e Autores | novas conexões | DROP + LOG | Anti-pivô: servidor comprometido não ataca a LAN |
| R11 | Qualquer | Qualquer | ESTABLISHED,RELATED | ACCEPT | Respostas de conexões autorizadas |
| R12 | Qualquer | Qualquer | qualquer | DROP + LOG | Negação padrão |
| INPUT | Editores | Firewall | ICMP echo-request | ACCEPT | Teste de conectividade; demais tráfego ao firewall é DROP |
| OUTPUT | Firewall | qualquer | — | DROP (exceto ESTABLISHED) | Firewall não inicia conexões |

> **Controle por segmento:** a comunicação API → db (5432) e API → cofre (80) ocorre dentro de `dmz_dados`, sem atravessar o firewall. Ela é controlada pela **associação de rede**: apenas a API pertence a dmz_web e dmz_dados ao mesmo tempo.

## 4. Metodologia de Testes e Validação

**Preparação**
```bash
docker compose up -d --build
docker compose ps        # firewall = healthy
```
**Execução automática:** `bash testes/validar.sh` (imprime PASS/FAIL e os contadores do firewall).

**Testes positivos (devem funcionar)**
| Teste | Comando | Resultado esperado |
|---|---|---|
| P1 | `docker compose exec estacao-editor curl -s -o /dev/null -w "%{http_code}" http://portal-web/` | 200 |
| P2 | `... estacao-editor curl -s http://api-editorial:5000/status` | `"db": "up"`, `"cofre": "up"` |
| P3 | `... autor-externo curl -s -X POST -d '{"titulo":"X"}' http://portal-web/api/submissao` | 201 + protocolo |
| P4 | `... estacao-editor curl -H "X-API-Token: <token>" http://api-editorial:5000/manuscritos/a-sombra-do-cerrado-cap01.txt` | conteúdo do manuscrito |

**Testes negativos (devem ser bloqueados)**
| Teste | Comando | Resultado esperado |
|---|---|---|
| N1 | `... estacao-editor nmap -Pn -p 5432 172.20.30.10` | `filtered` |
| N2 | `... estacao-editor curl -m 3 http://172.20.30.20/` | timeout (cofre inacessível) |
| N3 | `... autor-externo curl -m 3 http://172.20.20.20:5000/status` | timeout |
| N4 | `... autor-externo ping -c2 172.20.10.10` | 100% de perda |
| N5 | `... autor-externo nmap -Pn -p 22,80,443,5000,5432 172.20.20.10` | só a 80 `open` |
| N6 | `... autor-externo curl http://portal-web/api/status` | 403 |

**Evidências:** `docker compose exec firewall iptables -L FORWARD -n -v --line-numbers` (contadores das regras R5–R12 sobem após os testes negativos) e, em host Linux, `dmesg | grep FW-DROP`.

**Contraprova:** `docker compose stop firewall` derruba toda a comunicação entre redes, provando que ele é o único caminho.

## 5. Plano de commits sugerido
1. `chore: estrutura inicial e .gitignore`
2. `feat: redes segmentadas e firewall base no compose`
3. `feat: regras iptables com politica DROP`
4. `feat: portal Nginx e API na DMZ web`
5. `feat: banco e cofre na DMZ dados`
6. `feat: clientes (editor e autor externo) com rotas`
7. `test: script de validacao positiva/negativa`
8. `feat: logs LOGDROP e anti-spoofing`
9. `docs: README e relatorio tecnico`
