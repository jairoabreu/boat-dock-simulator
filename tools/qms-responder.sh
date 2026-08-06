#!/bin/bash
# qms-responder.sh — piloto RESPONDE às perguntas do terminal do card.
# Rodado pelo launchd (loop próprio, mais rápido que o /executar): para cada
# contexto, se houver card com pergunta do usuário SEM resposta, dispara uma
# sessão headless do Claude que lê a pergunta + o card, responde no terminal e,
# se for feedback acionável, implementa e devolve o card p/ "Em revisão".
#
# Fecha a pergunta só com `qms.py pilot-resposta` (pilot_resposta) — a narração
# do voo (pilot_log) NÃO conta como resposta. Sessão que falha não marca →
# a pergunta volta na próxima ronda.
#
# Usa a MESMA trava por contexto do /executar (.voo.lock): responder e executor
# nunca mexem no mesmo repo ao mesmo tempo. Uma pergunta feita durante um voo é
# respondida logo após o pouso (quando a trava libera).
LOG=~/MaTel/tools/logs/qms-responder.log
# MANTER EM SINC com qms-watch.sh
CONTEXTOS=(
  "$HOME/MaTel/matel-ivs-display-p4"    # 26 iVS-LCD10.1
  "$HOME/MaTel/matel-engine-panel"      # 18 iVS-LCD-StartStop
  "$HOME/MaTel/matel-ivs-gateway-fw"    #  9 CM06W
  "$HOME/CM2008"                        # 11 iVS-2008 (fora do ~/MaTel)
  "$HOME/MaTel-web_platform"            # 29 Plataforma Web reescrita
)

mkdir -p "$(dirname "$LOG")"

for d in "${CONTEXTOS[@]}"; do
  cd "$d" || continue
  L="$d/.claude/.voo.lock"
  # trava velha (>3h) = voo/resposta morta, limpa (mesma regra da vigia)
  if [ -d "$L" ] && [ -n "$(find "$L" -maxdepth 0 -mmin +180 2>/dev/null)" ]; then
    echo "$(date '+%F %T') [$(basename "$d")] trava velha removida" >> "$LOG"
    rm -rf "$L"
  fi
  # adquire a trava do contexto; se um voo (ou outra resposta) roda, pula
  mkdir "$L" 2>/dev/null || continue

  PENDING=$(python3 "$HOME/MaTel/tools/qms.py" perguntas 2>/dev/null)
  if [ -z "$PENDING" ]; then rm -rf "$L"; continue; fi

  # primeira tarefa com pergunta pendente + todas as perguntas dela
  TID=$(printf '%s\n' "$PENDING" | head -1 | cut -f1)
  QS=$(printf '%s\n' "$PENDING" | awk -F'\t' -v t="$TID" '$1==t {print "- " $2}')
  echo "$(date '+%F %T') [$(basename "$d")] respondendo pergunta(s) no card #$TID" >> "$LOG"

  # heredoc via `read` (evita o bug do $(cat <<EOF) com ')' no corpo no bash 3.2).
  # $TID/$QS/$HOME expandem; o resto é literal. read sai com 1 no EOF — ok aqui.
  IFS='' read -r -d '' PROMPT <<EOF || true
Você é o PILOTO deste card no MaTelQMS, falando pelo "terminal do piloto".
O usuário deixou perguntas/feedback no card #$TID que ainda NÃO foram respondidas:

$QS

Faça, nesta ordem:
1. Rode: python3 $HOME/MaTel/tools/qms.py tarefa $TID — para ver a descrição e as subtarefas do card; entenda o estado do repositório atual.
2. Responda CADA pergunta de forma objetiva e honesta. Suas mensagens de texto já aparecem como linhas no terminal do piloto.
3. Se for feedback ACIONÁVEL sobre o trabalho (um bug apontado ou um ajuste pedido), IMPLEMENTE a mudança no código, explique em 1-2 frases o que fez e mova o card para revisão: python3 $HOME/MaTel/tools/qms.py mover $TID revisão.
4. Não invente. Se não der para responder ou agir com segurança, diga o porquê e o que falta.
Seja conciso. Não faça commit/push a menos que o fluxo do projeto já faça isso.
EOF

  # VOO EM BACKGROUND (igual à vigia): lança e sai; a trava morre com a sessão.
  (
    cd "$d" || exit 1
    set -o pipefail
    if claude --dangerously-skip-permissions -p "$PROMPT" \
          --output-format stream-json --verbose < /dev/null 2>> "$LOG" \
          | python3 "$HOME/MaTel/tools/qms_narra.py" "$TID" "🛬 piloto retornou para responder" >> "$LOG"; then
      python3 "$HOME/MaTel/tools/qms.py" pilot-resposta "$TID" "✅ respondido pelo piloto" >> "$LOG" 2>&1 \
        || echo "$(date '+%F %T') [$(basename "$d")] pilot-resposta falhou — pergunta fica p/ nova tentativa" >> "$LOG"
    else
      echo "$(date '+%F %T') [$(basename "$d")] resposta FALHOU (login do CLI? rede?) — pergunta fica p/ nova tentativa" >> "$LOG"
    fi
    echo "$(date '+%F %T') [$(basename "$d")] card #$TID: resposta encerrada" >> "$LOG"
    rm -rf "$L"
  ) &
done
# NÃO usar wait: sai já; AbandonProcessGroup no plist preserva as sessões.
