# Resposta — prioridade dos papéis novos (§5.3 do handoff de vocês)

**Data:** 03/08/2026 · **De:** firmware da tela 10.1" · **Para:** plataforma

Vocês perguntaram a prioridade de `hvac_power`, `bilge_level` e `humidity`.
Do lado da tela os consumidores já estão implementados e no ar — cada papel
aparece sozinho no dia em que o `/hmi/config` o emitir, sem novo firmware.
A ordem que recomendamos, pelo que destrava:

1. **`do_role: "hvac_power"`** — é o que transforma a aba Ar-condicionado de
   prévia em produto: o switch de cada zona passa a acionar o relé de verdade
   (mesmo caminho não-otimista das luzes, com retentativa por confirmação).
   Hoje a aba inteira avisa que não aciona nada — a pior impressão em demo.
2. **`ai_role: "humidity"`** — tile UMIDADE no card da zona.

**`bilge_level` NÃO implementar** — retirado por decisão de produto (03/08):
bomba de porão não tem sensor de coluna d'água, tem BOIA — contato
liga/desliga. Nível analógico em % era artefato do desenho e já saiu da tela.

**NOVO — `di_role: "flood_sensor"` (SENSOR DE INUNDAÇÃO), 3º da lista.**
Nome de produto definido: a segunda boia, montada acima da principal, é o
sensor de inundação. O consumidor JÁ ESTÁ NO FIRMWARE (03/08): quando o
`/hmi/config` marcar uma entrada digital com `di_role: "flood_sensor"`, a
tela mostra uma faixa vermelha global por cima de todas as abas ("INUNDAÇÃO —
<área>: boia de água alta acionada") e a faixa da aba Bombas sobe de âmbar
para vermelho. O campo `invert` do canal é respeitado (fiação NA/NF da boia).
Do lado de vocês: emitir o papel no config + UI de cadastro; vale também
notificação push/e-mail quando o DI ativar — é o alarme mais grave do barco.

Detalhes de contrato: HANDOFF-climatizacao-bombas-tela-10.md §2.

Aproveitando: o **ETag/304 foi adotado e está funcionando ponta a ponta** —
medimos o primeiro 304 real hoje (1,3 s, corpo vazio). Uma ressalva de
implementação que pode interessar a vocês: o firmware só envia
`If-None-Match` quando o cache local existe — depois de um wipe local, um
304 seria "nada mudou" para uma tela sem nada, e o 304 não traz corpo.
