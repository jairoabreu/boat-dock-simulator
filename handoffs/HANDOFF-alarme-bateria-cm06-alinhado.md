# Handoff — alarme de bateria: o CM06 alinhou ao módulo, e a ponta está aberta

**Data:** 08/08/2026 · **Origem:** cartão #179 (gateway CM06, quadro 9) ·
**Para:** firmware do iVS-2408 (cartão #174, quadro 11), plataforma web / API
(cartão #173, quadro 29), `matel-gateway` (Go) e tela 10.1" (quadro 26)

**Resposta a** `HANDOFF-alarme-bateria-ivs2408-pronto.md` (§1 e §3).
**Substitui**, nos pontos abaixo, o `HANDOFF-alarme-bateria-cm06-pronto.md` (#175).

> **Resumo em uma linha:** as duas linhas do §1.1 mudaram, o `SIDE=normal` sobe,
> a repetição de 60 s **não** vira metralhadora de EVT, e as duas recusas novas
> chegam com nome. A cossimulação passou a rodar inteira contra o emulador de
> vocês: 42 conferências, 0 falhas.

## 1. O `lado` agora é o de vocês

```
0x00  RESERVADO, nunca emitido      0x02  hi
0x01  lo                            0x03  normal
```

Aceito integralmente, e pelo primeiro motivo mais do que pelo segundo: `0x00`
reservado é o que impede um quadro DLC 4 zerado de virar *"canal 0 cruzou o
mínimo em 0 mV"*. Lado que este firmware não conhece é **ignorado**, nunca
publicado como `lo` por omissão — mesma regra do DLC estranho.

O MT2 do alarme passa a ser:

```
MT2,<uin>,EVT,<seq>,ALM=<ch>,SIDE=<lo|hi|normal>,MV=<mV>,NODE=<xx>
```

**Autoridade do formato:** `docs/MT2-alarme-bateria.md` no `matel-ivs-gateway-fw`.

## 2. A repetição de 60 s é desduplicada AQUI — e a web precisa saber

O CM06 publica **uma linha por MUDANÇA de lado**, não uma por quadro recebido.
No barramento a repetição é feature; num link 4G seria um `EVT` idêntico por
minuto por canal em alarme, com custo de tráfego e de notificação.

O que isso quer dizer para quem consome:

- **um `ALM=` com `SIDE=lo` não se repete a cada minuto.** Se a sua vigia contava
  com isso como heartbeat da condição, não conte: o que encerra é o
  `SIDE=normal`;
- a memória é só o **último lado por (nó, canal)** e nasce vazia. Depois de um
  reboot do CM06 o primeiro alarme repetido republica — é exatamente para isso
  que a repetição de vocês serve deste lado do fio;
- enquanto o UIN do módulo ainda não foi ouvido (≤ 5 s do `ADDR_ANNOUNCE`) nada é
  lembrado: a linha não teria como subir, e marcá-la como publicada calaria o
  canal até a próxima mudança de lado.

Isto **não** é cache de configuração: os limites continuam sem cópia nenhuma
aqui, e o relatório segue sendo a única fonte do estado.

## 3. As duas recusas novas, com nome

| `I2008NK` | sobe como | `DET=` |
|---|---|---|
| `0x04 FAIXA_INVERTIDA` | `ERR=faixa_invertida` | `0` |
| `0x05 ACIMA_DO_MEDIVEL` | `ERR=acima_do_medivel` | o teto **em VOLTS** (25 hoje) |

O `DET` do 0x05 atravessa sem tradução, como o teto de bobinas do #159.
**A nuvem não deve cravar o 25** — é o número de quem o aplica, e é assim que um
lote com entrada de faixa maior o muda sem release nenhum. Registrado em
`docs/MT2-recusa-de-comando.md`.

## 4. A cossimulação virou inteira, e o substituto foi embora

O `alarme_bateria_cosim.py` não tem mais lado de mentira: as duas pontas são
código de produção de dois produtos. Se o emulador regredir e perder o `0x4B`, o
script **para** em vez de instalar um par que segue o palpite do CM06 — foi
exatamente essa a armadilha que produziu o #179. Ele também confere, na partida,
se os três valores de `lado` batem dos dois lados.

**42 conferências, 0 falhas** (08/08/2026), incluindo os dois sentidos, o
`normal`, o canal sem fio não recuperando, e a repetição de vocês chegando ao
barramento **sem** virar EVT.

As janelas de 3 s e 60 s são **encolhidas** por `args.alarm_confirm_s` /
`args.alarm_repeat_s` — obrigado por elas. Os dois números têm prova própria no
`alarme_sim.py` e na bancada de vocês; o que este teste prova é o protocolo, e
esperar 60 s de relógio não provaria nada a mais. Por isso o `RESP_S` não subiu
para 5 s: ele deixou de ser o teto que importa.

Não-vacuidade: com o `main/` de antes deste cartão caem **10 das 42** — o `lo` de
vocês subindo como `hi`, os três `normal` ausentes, a repetição virando EVT e as
duas recusas voltando como `ERR=recusado`.

## 5. O que ainda falta, e é nosso

**A CM06 física não foi gravada.** Tudo acima é hospedeiro + emulador. A gravação
acumula com os cartões #158, #160 e #162 e sai numa passada só quando o USB da
placa for plugado. O que ela vai provar que a cossimulação não prova é o
barramento de verdade: temporização de TWAI, quadro concorrente, e o alarme
saindo do módulo real para o rastreador real.

Do lado de vocês, do §5 do handoff anterior, continua valendo o pedido inverso —
se a régua dos 0,5 V ou a banda morta mudarem, elas estão escritas em
`docs/MT2-alarme-bateria.md` também.
