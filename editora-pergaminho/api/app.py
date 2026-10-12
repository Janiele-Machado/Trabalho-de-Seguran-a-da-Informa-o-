"""API da Editora Pergaminho (somente biblioteca padrao).
Unico servico que enxerga a DMZ web E a rede de dados (db + cofre)."""
import hmac, json, os, socket, urllib.request, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.getenv("API_TOKEN", "")
DB_HOST = os.getenv("DB_HOST", "db")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
COFRE = os.getenv("COFRE_URL", "http://cofre")


def tcp_ok(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def cofre_get(nome):
    with urllib.request.urlopen(f"{COFRE}/{nome}", timeout=3) as r:
        return r.read()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, {"status": "ok"})

        if self.path == "/status":
            try:
                cofre_get("index.html"); cofre = "up"
            except Exception:
                cofre = "down"
            return self._send(200, {
                "api": "ok",
                "db": "up" if tcp_ok(DB_HOST, DB_PORT) else "down",
                "cofre": cofre,
            })

        if self.path.startswith("/manuscritos/"):
            enviado = self.headers.get("X-API-Token", "")
            if not TOKEN or not hmac.compare_digest(enviado, TOKEN):
                return self._send(401, {"erro": "token invalido"})
            nome = os.path.basename(self.path[len("/manuscritos/"):])
            try:
                return self._send(200, cofre_get(nome), "text/plain; charset=utf-8")
            except Exception:
                return self._send(404, {"erro": "nao encontrado"})

        return self._send(404, {"erro": "rota inexistente"})

    def do_POST(self):
        if self.path != "/submissao":
            return self._send(404, {"erro": "rota inexistente"})
        n = int(self.headers.get("Content-Length", 0))
        if n > 65536:
            return self._send(413, {"erro": "payload grande demais"})
        try:
            dados = json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return self._send(400, {"erro": "json invalido"})
        if not str(dados.get("titulo", "")).strip():
            return self._send(400, {"erro": "titulo obrigatorio"})
        return self._send(201, {"protocolo": uuid.uuid4().hex[:12],
                                "mensagem": "Proposta recebida pela Editora Pergaminho."})


if __name__ == "__main__":
    print("API ouvindo em :5000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 5000), Handler).serve_forever()
