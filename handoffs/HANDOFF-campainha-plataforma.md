# Handoff — interruptor de campainha na plataforma: o que a web precisa receber

**Data:** 08/08/2026 · **Origem:** cartão #154 (plataforma web, quadro 29) ·
**Para:** gateway CM06 (`matel-ivs-gateway-fw`), gateway Go (`matel-gateway`)
e API (`matel-api`)

Resposta ao `HANDOFF-funcao-pulso-ivs2008.md` (#140). A plataforma já modelou a
configuração, desenhou a tela do instalador e passou a consumir a recusa que
não tem comando por trás. **O que ela não tem é como ligar a função nem como
ler a configuração** — o elo do meio não existe. Este documento é o contrato
que a web quer consumir, para que os dois cartões anteriores da cadeia não
precisem adivinhar a forma.

Estado da cadeia:

| # | onde | o que falta | quem |
|---|------|-------------|------|
| 1 | CM06 | comando MT2 de escrita/consulta do I2008IF (0x4E) + publicar o relatório | `matel-ivs-gateway-fw` **(bloqueio de tudo)** |
| 2 | Go + API | transporte, persistência e evento ao vivo | `matel-gateway` / `matel-api` |
| 3 | web | ligar o botão da tela ao envio | quadro 29, depois de 1 e 2 |

## 1. O que o CM06 precisa falar (proposta de MT2)

Mesma família dos comandos que já existem, para não inventar tipo novo:

```
escrita:   MT2,<uin>,CMD,<seq>,IF,CH=<0..7>,FN=<0|1>
consulta:  MT2,<uin>,CMD,<seq>,IF?
relatório: MT2,<uin>,IF,<mascara_hex>          ← difusão, a cada escrita aceita
                                                  e a cada consulta
```

- `FN`: `0` = nenhuma, `1` = inverter o relé do par. O `0x5A` de trava é
  assunto do barramento CAN — não sobe.
- Canal 0-based, e só `0..7`. Canal ≥ 8 tem de voltar
  `ACK,<seq>,ERR=fora_de_faixa,DET=8`, que a web já traduz hoje.
- O relatório é o ÚNICO estado que vale. A web não deriva máscara do que
  mandou: essa regra está escrita e testada em
  `apps/nautica/src/lib/api/io-campainha.ts`.

## 2. O que a API precisa expor

**Leitura + consulta (uma coisa só).** Abrir a tela do instalador é perguntar
ao módulo:

```
GET /devices/{device_id}/io/campainha?uin=<uin>
→ 200 { "uin": 2608070000, "node_id": 70, "mascara": 5,
        "lido_em": "2026-08-08T12:00:00Z" }
→ 204 quando o módulo nunca relatou
```

`lido_em` é obrigatório e é o carimbo do RELATÓRIO, não o da linha no banco:
é ele que diz à web se a resposta ainda vale (`VALIDADE_RELATORIO_MS`, 60 s).
Um GET com cache velho deve disparar a consulta no barramento e responder o
que tiver — a web repergunta.

**Escrita.**

```
PUT /devices/{device_id}/io/campainha
    { "uin": 2608070000, "channel": 0, "enabled": true }
→ 202 { "command_id": "…" }
```

Destino por `uin`, como todo o resto desde o #125 — endereço só para o parque
legado. O desfecho vem pelo `command_result` que já existe; o estado NOVO vem
pelo relatório, não pela resposta do PUT.

**Persistência.** O que a nuvem guardar é cache de uma memória que é do
módulo. Guarde a máscara **por UIN**, nunca por endereço de nó, e guarde o
instante do relatório junto — sem ele a web não tem como saber se pode
confiar. Módulo trocado tem UIN novo, e é isso que faz a resposta antiga não
ser herdada pela placa nova.

## 3. O evento de recusa sem comando (`ORIG=local`)

```
MT2,<uin>,EVT,<seq>,NACK=<motivo>,CH=<n>,DET=<n>,OP=00,ORIG=local
```

A web **já consome isto hoje**, mas pelo caminho torto: o gateway publica o
`EVT` só no stream de frames crus, então `io-actions.ts` lê o texto do
`raw_frame`, confere o UIN contra os módulos do casco e avisa o operador
(`recusaDeEvento`, em `lib/api/io-refusal.ts`). Funciona, e é frágil por
depender do espelho de debug.

O que se pede:

1. **Um evento de primeira classe no WS** — `kind: "io_event"`, com `uin`,
   `node_id`, `channel`, `reason`, `detail`, `origin` já decompostos. A web
   troca o parser pelo campo e nada mais muda.
2. **Registro durável.** Toast é efêmero; a queixa do handoff é que "não fica
   registro nenhum". O evento merece linha no catálogo de eventos de protocolo
   (categoria `io`), para o operador achar depois no relatório o motivo de a
   luz não ter acendido às 22h.
3. **`DET` adiante, sempre.** É o teto de bobinas em vigor. A web aprende o
   número por UIN e para de cravar o 6 — inclusive a partir do EVT, porque um
   toque recusado consome o mesmo orçamento de corrente que um comando.

## 4. Um pedido sobre severidade

Com a função ligada, **o `do_mask` passa a mudar sem comando nenhum** — alguém
apertou um botão na parede. Isso não é anomalia, é o estado do barco.

Conferido do lado da web (#154): nada na plataforma classifica mudança sem
comando em voo como erro — `io-actions.ts` só olha para comandos pendentes, e
nenhum gatilho de automação escuta I/O. Quem ainda precisa concordar é o
catálogo de eventos do backend: um evento de saída que nasça com severidade
`alarm` vai encher a caixa do cliente de alarme toda vez que acenderem a luz
do salão.

## 5. Detalhe fino para quando o relatório existir

A web avisa "o módulo aceitou o comando, mas a saída N não mudou" quando o
`do_mask` não confirma em 20 s. Com o interruptor de campainha ligado naquele
canal existe um terceiro desfecho: o relé ligou e alguém o desligou na parede
antes do snapshot seguinte. Distinguir exige saber que a função está ligada
NAQUELE canal — ou seja, exige o relatório do item 1. Está registrado no
código (`io-actions.ts`, no timeout) para não se perder.

## Onde isto está do lado da web (cartão #154)

- `apps/nautica/src/lib/api/io-campainha.ts` — modelo: par posicional, estado
  do módulo, releitura em vez de cache cego. Testes em
  `apps/nautica/tests/io-campainha.test.ts`.
- `apps/nautica/src/lib/api/io-refusal.ts` — `recusaDeEvento` e as mensagens
  da recusa sem comando.
- `apps/nautica/src/components/iot/IoChannelsConfig.tsx` — a tela do
  instalador, com o par IN(N)→OUT(N) escrito e o estado do módulo.
- Nome na interface: **"interruptor de campainha"**. Nunca "pulso" sozinho —
  o gateway já usa a palavra para o pulso de SAÍDA (`IVS,SET,…,1,<ms>`).
