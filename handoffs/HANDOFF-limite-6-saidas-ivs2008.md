# Handoff — iVS2008 para em 6 saídas ligadas e ainda responde `ACK,OK`

**Data:** 08/08/2026 · **Origem:** cartão #106 (Plataforma Web, projeto 29)
**Bancada:** DOT460 `862092066689393` + iVS2008 **uin 2608070000 @ 0x46** (dev)
**Para:** contexto do firmware do iVS2008 (módulo de relés 20 A)

## Sintoma relatado

> "Só consigo acionar 6 saídas no máximo; quando tento acionar a próxima o
> comando diz que foi, mas não funciona."

## O que a plataforma mediu

A sequência abaixo saiu de `device_commands` + `io_telemetry` do ambiente dev,
janela 08/08/2026 01:15:50–01:16:08 UTC. Todos os comandos foram pela via MT2 e
**todos voltaram `acked`**.

| seq | frame enviado | resposta do módulo | `do_mask` reportado |
|---|---|---|---|
| 0006 | `MT2,2608070000,CMD,0006,OP=SET,CH=0,ST=1` | `ACK,0006,OK` | `0x01` |
| 0007 | `…,CH=1,ST=1` | `ACK,0007,OK` | `0x03` |
| 0008 | `…,CH=2,ST=1` | `ACK,0008,OK` | `0x07` |
| 0009 | `…,CH=3,ST=1` | `ACK,0009,OK` | `0x0F` |
| 000A | `…,CH=7,ST=1` | `ACK,000A,OK` | `0x8F` |
| 000B | `…,CH=6,ST=1` | `ACK,000B,OK` | `0xCF` ← **6 saídas** |
| 000C | `…,CH=5,ST=1` | `ACK,000C,OK` | `0xCF` — **não mudou** |
| 000D | `…,CH=5,ST=1` (repetido) | `ACK,000D,OK` | `0xCF` — **não mudou** |
| 000E | `…,CH=4,ST=1` | `ACK,000E,OK` | `0xCF` — **não mudou** |

Depois, com tudo desligado, `CH=4,ST=1` levou a máscara a `0x10` e `CH=5,ST=1`
a `0x30`. **Os canais 4 e 5 funcionam perfeitamente sozinhos** — o que trava
não é canal nenhum, é a **contagem**.

Confirmação sobre todo o histórico do nó (`io_telemetry`, node 70):

```
saídas ligadas simultaneamente | amostras
             0 | 1426
             1 |  988
             2 |   46
             3 |   43
             4 |   20
             5 |   15
             6 |   31
             7 |    0     ← nunca aconteceu
             8 |    0     ← nunca aconteceu
```

## Causa — confirmada no fonte (não é bug)

O plantão localizou o limite no firmware V5 em Rust deste módulo
(`CM2008/Firmware/V5-rs`), e ele é **deliberado**:

- `digital.rs:29` — `MAX_SIMULTANEOUS_OUTPUTS = 6`, proteção do rail de
  **5 V / 1 A** que alimenta as bobinas.
- `digital.rs:115` — `set_state` devolve `false` na sétima bobina.
- `processor.rs:361` — a recusa só vira `defmt::warn` na serial. **Nada sai no
  barramento CAN e nenhum NACK sobe para a nuvem.**

Ou seja: o `ACK,OK` responde ao *recebimento* do comando MT2; a recusa acontece
depois, localmente, e morre calada. O `do_mask` continua dizendo a verdade — foi
por isso que a medição acima fecha com o fonte.

Nada no caminho da nuvem conta saídas: a plataforma manda um `OP=SET` por canal
e o gateway escreve `cm_write_outputs(node, 1<<ch, 1<<ch)`.

## O que se pede ao firmware (cartão do quadro 11 — iVS-2408 — + gateway)

**Anunciar a recusa.** Hoje o operador não tem como distinguir "ligou" de
"ignorei em silêncio", e a nuvem só descobre por ausência de mudança na máscara.
O pedido é um **NACK com motivo no MTCP** quando `set_state` devolve `false`, e
o gateway propagando isso para o `command_result` — a plataforma já sabe exibir
recusa com motivo (`failed` vira toast com o texto do erro).

Se 6 for pouco para o uso real, aí é decisão de **hardware** (orçamento de
corrente), não de software.

## O que a plataforma fez (#106)

Duas coisas, ambas em `apps/nautica/src/lib/api/io-actions.ts`
(repo `MaTel-web_platform`):

1. **O `ACK` deixou de ser o desfecho de um relé** — quem encerra é o `do_mask`
   reportado depois. Comando confirmado cuja máscara não muda em 20 s avisa *"O
   módulo aceitou o comando, mas a saída N não mudou de estado"*, em vez do
   "Ligando…" que ficava para sempre.
2. **Aviso ANTES do clique morrer calado** — com 6 saídas já ligadas, ligar mais
   uma nem chega a virar comando: *"O módulo liga no máximo 6 saídas ao mesmo
   tempo. Desligue uma antes de ligar esta."* Desligar nunca é barrado.

O teto continua sendo do módulo — isso só acaba com a mentira na tela. Quando o
NACK existir, a web passa a mostrar o motivo vindo do próprio firmware e o
número 6 sai do código da nuvem (`MAX_SAIDAS_SIMULTANEAS`, `lib/api/iot.ts`).
