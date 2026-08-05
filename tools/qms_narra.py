#!/usr/bin/env python3
"""qms_narra.py — narrador do piloto: stream do claude -> terminal do cartão.

Uso (pelo vigia): claude ... --output-format stream-json --verbose | qms_narra.py <task_id>

Lê o stream de eventos do claude headless no stdin, traduz cada evento numa
linha de narração pt-BR e a POSTA no MaTelQMS como `pilot_log` da tarefa —
é o que alimenta o "terminal do piloto" dentro do card. Também repassa um
resumo legível ao stdout (vai p/ o qms-watch.log). Falha de POST nunca
derruba o voo: a linha é descartada e o trabalho segue.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qms  # login/req/cfg_projeto — mesma CLI dos comandos


def resumo_ferramenta(nome, inp):
    if nome == "Bash":
        d = (inp.get("description") or "").strip()
        return d if d else (inp.get("command") or "")[:100]
    if nome in ("Edit", "Write", "Read", "NotebookEdit"):
        p = inp.get("file_path", "")
        acao = {"Edit": "editando", "Write": "escrevendo", "Read": "lendo",
                "NotebookEdit": "editando"}[nome]
        return f"{acao} {os.path.basename(p)}" if p else acao
    if nome == "Grep":
        return f"procurando '{(inp.get('pattern') or '')[:60]}'"
    if nome == "Glob":
        return f"listando {inp.get('pattern', '')}"
    if nome == "TodoWrite":
        return None                        # ruído interno, não narra
    return nome


def main():
    if len(sys.argv) < 2:
        sys.exit("uso: qms_narra.py <task_id>")
    tid = int(sys.argv[1])
    tok = None
    pid = None

    def posta(texto):
        nonlocal tok, pid
        texto = (texto or "").strip()
        if not texto:
            return
        try:
            if tok is None:
                tok = qms.login()
                pid = qms.cfg_projeto()
            qms.req("POST", f"/projects/{pid}/activities", token=tok,
                    body={"action": "pilot_log", "entity_type": "task",
                          "entity_id": tid, "payload": {"texto": texto[:1500]}})
        except SystemExit:
            # req/login usam falha() (sys.exit) — narrador nunca derruba o voo
            tok = None
        except Exception:
            tok = None

    posta("🛫 voo iniciado")
    for ln in sys.stdin:
        ln = ln.strip()
        if not ln:
            continue
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        t = ev.get("type")
        if t == "assistant":
            for bl in (ev.get("message") or {}).get("content") or []:
                if bl.get("type") == "text" and bl.get("text", "").strip():
                    txt = bl["text"].strip()
                    posta(txt)
                    print(txt[:200], flush=True)
                elif bl.get("type") == "tool_use":
                    r = resumo_ferramenta(bl.get("name", "?"),
                                          bl.get("input") or {})
                    if r:
                        posta(f"▸ {r}")
        elif t == "result":
            ok = ev.get("subtype") == "success"
            posta("🛬 voo encerrado" if ok
                  else f"⚠️ voo interrompido ({ev.get('subtype')})")
            print(f"[narrador] resultado: {ev.get('subtype')}", flush=True)
            sys.exit(0 if ok else 1)
    # stream acabou sem evento result = o claude morreu no meio
    posta("⚠️ voo interrompido (stream cortado)")
    sys.exit(1)


if __name__ == "__main__":
    main()
