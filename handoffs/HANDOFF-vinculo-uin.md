# HANDOFF — Vínculo por UIN (identidade ≠ endereço de barramento)

**Data:** 07/08/2026 · **Motivado por:** bug #125 (duas placas no mesmo endereço;
tela comandando o módulo errado) · **Produtos:** plataforma web, CM06, tela 10.1",
iVS2008/2408 (módulo já pronto — só anuncia).

## Princípio
O **UIN** (serial de produção, formato AAMMDDSSSS, u64) é a ÚNICA identidade de
um módulo. O endereço de barramento (0x41-0x4F) é transporte: dinâmico,
renegociável, NUNCA persistido como vínculo de função.

## O que já existe no fio
- Inventário MTCP: o módulo anuncia (endereço, serial u64 LE) ao reivindicar.
  Após o fix do #125, a arbitragem re-verifica colisões — o inventário reflete
  a verdade em regime.

## Contrato novo
1. **Plataforma** — cada canal do `/hmi/config` ganha `"uin"` (número, u64)
   ao lado do `node_id` (que fica por compatibilidade durante a transição;
   consumidor novo prefere `uin`). Comandos remotos (plataforma→CM06) carregam
   `uin`, nunca endereço.
2. **CM06** — mantém tabela viva UIN↔endereço a partir do inventário; resolve
   na injeção do comando. UIN ausente do barramento = comando RECUSADO com
   erro explícito à plataforma ("módulo <uin> ausente") — nunca redirecionado.
3. **Tela** — mesma tabela viva (RAM + último mapeamento na NVS p/ boot);
   escrita local resolve UIN→endereço no toque; UIN ausente = feedback
   "módulo ausente" no botão (a tela não mente). `cm_resolve_node` (redireção
   por palpite) é APOSENTADO. A tela reporta o inventário à plataforma junto
   do próximo ciclo de config, fechando o cadastro.
4. **Módulo** — nada muda: já anuncia. (V4 de campo precisa do backport do
   fix de arbitragem do #125 — cartão próprio.)

## Regra de honestidade compartilhada
Resolução falhou = falha declarada com o UIN no texto. Nenhuma ponta chuta
endereço. Logs sempre com os dois: "uin 2608070000 @ 0x46".
