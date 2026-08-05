#!/bin/bash
# qms-watch.sh — piloto automático do kanban MaTelQMS.
# Rodado pelo launchd a cada 15 min: para cada contexto de produto, se houver
# cartão do usuário Claude em "A fazer", dispara uma sessão headless do Claude
# que executa o fluxo /executar (implementa, reporta no cartão, deixa em
# "Em revisão" para o Jairo concluir). Um cartão por rodada, uma rodada por vez.
LOG=~/MaTel/tools/logs/qms-watch.log
CONTEXTOS=(
  "$HOME/MaTel/matel-ivs-display-p4"    # 26 iVS-LCD10.1
  "$HOME/MaTel/matel-engine-panel"      # 18 iVS-LCD-StartStop
  "$HOME/MaTel/matel-ivs-gateway-fw"    #  9 CM06W
  "$HOME/CM2008"                        # 11 iVS-2008 (fora do ~/MaTel)
  "$HOME/MaTel-web_platform"            # 29 Plataforma Web reescrita (contexto Nautica)
)
# matel-mobile e CM01 entram quando os quadros deles existirem no QMS

mkdir -p "$(dirname "$LOG")"

# rede de segurança: quadro novo com cartão do Claudio e sem contexto? grita.
IDS=$(for d in "${CONTEXTOS[@]}"; do python3 -c "import json;print(json.load(open('$d/.claude/qms.json'))['project_id'] or '')" 2>/dev/null; done | tr '\n' ' ')
cd "${CONTEXTOS[0]}" && python3 "$HOME/MaTel/tools/qms.py" orfaos $IDS 2>/dev/null | while read -r av; do
  echo "$(date '+%F %T') $av" >> "$LOG"
done

for d in "${CONTEXTOS[@]}"; do
  cd "$d" || continue
  # TRAVA POR CONTEXTO: um voo por produto, produtos em paralelo — cartão web
  # não espera voo de firmware (05/08/2026). Trava >3h = voo morto, limpa.
  L="$d/.claude/.voo.lock"
  if [ -d "$L" ] && [ -n "$(find "$L" -maxdepth 0 -mmin +180 2>/dev/null)" ]; then
    echo "$(date '+%F %T') [$(basename "$d")] trava velha removida" >> "$LOG"
    rm -rf "$L"
  fi
  mkdir "$L" 2>/dev/null || continue
  trap 'rm -rf "$L"' EXIT
  id=$(python3 "$HOME/MaTel/tools/qms.py" proxima 2>/dev/null) || { rm -rf "$L"; trap - EXIT; continue; }
  echo "$(date '+%F %T') [$(basename "$d")] cartão #$id atribuído — executando" >> "$LOG"
  set -o pipefail
  if ! claude --dangerously-skip-permissions -p "/executar $id" \
        --output-format stream-json --verbose < /dev/null 2>> "$LOG" \
        | python3 "$HOME/MaTel/tools/qms_narra.py" "$id" >> "$LOG"; then
    echo "$(date '+%F %T') [$(basename "$d")] FALHOU (login do CLI? rede?) — cartão fica em A fazer p/ nova tentativa" >> "$LOG"
  fi
  echo "$(date '+%F %T') [$(basename "$d")] cartão #$id: sessão encerrada (veja o resultado no quadro)" >> "$LOG"
  rm -rf "$L"; trap - EXIT
done
