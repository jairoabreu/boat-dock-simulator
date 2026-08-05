#!/usr/bin/env python3
"""qms.py — ponte dos contextos de produto com o kanban de projetos do MaTelQMS.

Cada repo de produto tem um .claude/qms.json com o project_id do seu quadro em
https://matel.ind.br/projetos/<id>. As credenciais do usuário de serviço
"Claude" ficam FORA de qualquer git, em ~/.config/matelqms/claude.json:
    { "email": "claude@matel.ind.br", "senha": "..." }

Uso (sempre a partir de dentro do repo do produto):
    qms.py projetos                     lista projetos visíveis (p/ mapear id)
    qms.py demandas [todas]             minhas tarefas (ou o quadro inteiro)
    qms.py proxima                      id do próximo cartão meu em "A fazer"
                                        (só o número; sai 1 se não houver)
    qms.py tarefa <id>                  detalhe: descrição + subtarefas
    qms.py mover <id> <coluna>          move o cartão (nome parcial serve)
    qms.py resultado <id> <texto...>    anexa "Resultado (Claude)" à descrição

Sem dependências além da stdlib (urllib) — roda em qualquer contexto.
"""
import json
import os
import sys
import ssl
import urllib.request
import urllib.error
from datetime import datetime, timezone

# O Python do instalador python.org no macOS não enxerga os certificados do
# sistema — sem isto, TODA chamada morria em CERTIFICATE_VERIFY_FAILED.
try:
    import certifi
    _CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _CTX = ssl.create_default_context()

BASE = os.environ.get("MATELQMS_URL", "https://matel.ind.br/api/v1")
CRED = os.path.expanduser("~/.config/matelqms/claude.json")


def falha(msg):
    print(f"ERRO: {msg}")
    sys.exit(1)


def req(method, path, token=None, body=None):
    r = urllib.request.Request(BASE + path, method=method)
    r.add_header("Content-Type", "application/json")
    if token:
        r.add_header("Authorization", f"Bearer {token}")
    data = json.dumps(body).encode() if body is not None else None
    for tentativa in (1, 2):
        try:
            with urllib.request.urlopen(r, data, timeout=30, context=_CTX) as resp:
                txt = resp.read().decode()
                return json.loads(txt) if txt else {}
        except urllib.error.HTTPError as e:
            detalhe = e.read().decode()[:300]
            falha(f"HTTP {e.code} em {method} {path}: {detalhe}")
        except (urllib.error.URLError, TimeoutError) as e:
            if tentativa == 2:
                falha(f"sem alcançar {BASE}: {e}")
            # servidor acordando/rede piscou: uma retentativa resolve o comum


def login():
    if not os.path.exists(CRED):
        falha(f"credenciais ausentes em {CRED}\n"
              "Crie o arquivo: {\"email\": \"...\", \"senha\": \"...\"} "
              "(usuário de serviço 'Claude' do MaTelQMS)")
    c = json.load(open(CRED))
    resp = req("POST", "/auth/login",
               body={"email": c["email"], "password": c["senha"]})
    tok = resp.get("access_token") or resp.get("token")
    if not tok:
        falha(f"login não devolveu token: {str(resp)[:200]}")
    return tok


def cfg_projeto():
    """Sobe do cwd procurando .claude/qms.json (o repo do produto)."""
    d = os.getcwd()
    while d != "/":
        p = os.path.join(d, ".claude", "qms.json")
        if os.path.exists(p):
            c = json.load(open(p))
            if not c.get("project_id"):
                falha(f"{p} sem project_id — rode 'qms.py projetos', ache o "
                      "quadro deste produto e preencha o id lá")
            return c["project_id"]
        d = os.path.dirname(d)
    falha("nenhum .claude/qms.json daqui até a raiz — rode de dentro do repo "
          "do produto")


def quem_sou(tok):
    """id do usuário de serviço logado — as demandas são filtradas por ele."""
    me = req("GET", "/auth/me", token=tok)
    return me.get("id"), me.get("name", "Claude")


def quadro(tok, pid):
    return req("GET", f"/projects/{pid}", token=tok)


def acha_tarefa(p, tid):
    for col in p.get("columns", []):
        for t in col.get("tasks", []):
            if t["id"] == tid:
                return col, t
    falha(f"tarefa {tid} não está no quadro '{p.get('name')}'")


def cmd_projetos(tok):
    ps = req("GET", "/projects", token=tok)
    itens = ps if isinstance(ps, list) else ps.get("items", ps.get("projects", []))
    for p in itens:
        print(f"  {p['id']:>4}  {p.get('name','?')}"
              f"{'  [arquivado]' if p.get('archived') else ''}")


def cmd_demandas(tok, pid, todas=False):
    """Por padrão SÓ as tarefas cujo responsável é o usuário de serviço logado
    — é o que permite vários "Claudes" dividirem o mesmo quadro sem um pegar
    o cartão do outro. `demandas todas` mostra o quadro inteiro."""
    meu_id, meu_nome = quem_sou(tok)
    p = quadro(tok, pid)
    print(f"QUADRO: {p.get('name')} (projeto {pid})"
          + ("" if todas else f" — tarefas de {meu_nome}"))
    ocultas = 0
    for col in p.get("columns", []):
        ts = col.get("tasks", [])
        if not todas:
            minhas = [t for t in ts
                      if (t.get("assignee") or {}).get("id") == meu_id]
            ocultas += len(ts) - len(minhas)
            ts = minhas
        print(f"\n== {col.get('title')} ({len(ts)}) ==")
        for t in ts:
            subs = t.get("subtasks", [])
            feitas = sum(1 for s in subs if s.get("done"))
            extra = []
            if t.get("priority"):
                extra.append(t["priority"])
            if subs:
                extra.append(f"sub {feitas}/{len(subs)}")
            if t.get("assignee"):
                extra.append(t["assignee"].get("name", ""))
            print(f"  #{t['id']:<5} {t['title']}"
                  f"{('  [' + ', '.join(extra) + ']') if extra else ''}")
    if ocultas:
        print(f"\n({ocultas} tarefa(s) de outros responsáveis ocultas — "
              "veja tudo com: qms.py demandas todas)")


def cmd_proxima(tok, pid):
    """Próximo cartão MEU: primeiro os órfãos em 'Em andamento' (o vigia roda
    UMA sessão por vez — cartão meu em andamento sem sessão viva = a anterior
    morreu no meio; retomar), depois os novos em 'A fazer'. Saída crua — é o
    gatilho do vigia (tools/qms-watch.sh)."""
    meu_id, _ = quem_sou(tok)
    p = quadro(tok, pid)
    cols = p.get("columns", [])
    PRIO = {"high": 0, "med": 1, "low": 2}
    def minha(col_substr):
        """Minhas tarefas da coluna, por PRIORIDADE (high>med>low>sem) e, no
        empate, pela POSIÇÃO no quadro (de cima p/ baixo — a API já entrega
        ordenado por position; o sort é estável e preserva isso)."""
        hit = [c for c in cols if col_substr in c.get("title", "").lower()]
        minhas = [t for t in (hit[0].get("tasks", []) if hit else [])
                  if (t.get("assignee") or {}).get("id") == meu_id]
        minhas.sort(key=lambda t: PRIO.get(t.get("priority"), 3))
        return minhas[0]["id"] if minhas else None
    tid = minha("andamento")
    if tid is None:
        tid = minha("fazer")
    # Fallback p/ 1ª coluna SÓ em quadro sem coluna "fazer" nenhuma. Quando
    # "A fazer" existe e está vazia, vazio é a resposta: Backlog e afins são
    # ANTESSALA — cartão lá não dispara nem atribuído (05/08/2026: o fallback
    # antigo pescou um cartão do Backlog recém-criado).
    tem_fazer = any("fazer" in c.get("title", "").lower() for c in cols)
    if tid is None and not tem_fazer and cols:
        for t in cols[0].get("tasks", []):
            if (t.get("assignee") or {}).get("id") == meu_id:
                tid = t["id"]; break
    if tid is None:
        sys.exit(1)
    print(tid)


def cmd_tarefa(tok, pid, tid):
    meu_id, _ = quem_sou(tok)
    p = quadro(tok, pid)
    col, t = acha_tarefa(p, tid)
    a = t.get("assignee") or {}
    if a.get("id") != meu_id:
        print(f"⚠️  responsável desta tarefa: {a.get('name') or 'ninguém'} — "
              "NÃO é o usuário Claude deste posto. Confirme antes de executar.")
    print(f"#{t['id']} — {t['title']}\ncoluna: {col.get('title')}"
          f" | prioridade: {t.get('priority') or '—'}"
          f" | prazo: {t.get('due_date') or '—'}")
    if t.get("description"):
        print(f"\n{t['description']}")
    subs = t.get("subtasks", [])
    if subs:
        print("\nSubtarefas:")
        for s in subs:
            print(f"  [{'x' if s.get('done') else ' '}] ({s['id']}) {s['title']}")


def cmd_mover(tok, pid, tid, alvo):
    p = quadro(tok, pid)
    _, t = acha_tarefa(p, tid)
    alvo_l = alvo.lower()
    cols = p.get("columns", [])
    hit = [c for c in cols if alvo_l in c.get("title", "").lower()]
    if not hit and ("conclu" in alvo_l or alvo_l == "done"):
        hit = [c for c in cols if c.get("is_done")]   # coluna marcada como done
    if not hit:
        falha(f"coluna '{alvo}' não existe; opções: "
              + ", ".join(c.get("title", "?") for c in cols))
    dest = hit[0]
    req("POST", f"/projects/tasks/{tid}/move", token=tok,
        body={"column_id": dest["id"], "position": 0})
    print(f"#{tid} -> '{dest['title']}'")


def cmd_resultado(tok, pid, tid, texto):
    p = quadro(tok, pid)
    _, t = acha_tarefa(p, tid)
    agora = datetime.now(timezone.utc).astimezone().strftime("%d/%m/%Y %H:%M")
    desc = (t.get("description") or "").rstrip()
    desc += f"\n\n---\n**Resultado (Claude, {agora}):** {texto}\n"
    req("PUT", f"/projects/tasks/{tid}", token=tok, body={"description": desc})
    print(f"#{tid}: resultado registrado")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)
    cmd = sys.argv[1]
    tok = login()
    if cmd == "projetos":
        return cmd_projetos(tok)
    pid = cfg_projeto()
    if cmd == "proxima":
        return cmd_proxima(tok, pid)
    if cmd == "demandas":
        return cmd_demandas(tok, pid, todas=(len(sys.argv) > 2 and
                                             sys.argv[2] == "todas"))
    if cmd == "tarefa" and len(sys.argv) > 2:
        return cmd_tarefa(tok, pid, int(sys.argv[2]))
    if cmd == "mover" and len(sys.argv) > 3:
        return cmd_mover(tok, pid, int(sys.argv[2]), " ".join(sys.argv[3:]))
    if cmd == "resultado" and len(sys.argv) > 3:
        return cmd_resultado(tok, pid, int(sys.argv[2]), " ".join(sys.argv[3:]))
    print(__doc__)
    sys.exit(1)


if __name__ == "__main__":
    main()
