# Handoff — horímetro das bombas vem do iVS2008 agora

**Data:** 02/08/2026
**De:** firmware do iVS2008 (`~/CM2008`) + gateway CM06 + plataforma
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)

> **Resumo em uma linha:** o iVS2008 passou a contar tempo ligado e partidas
> das 12 DIs por conta própria e a publicar no CAN (opcode **`0x4D`**). A tela
> pode parar de contar sozinha e passar a ler.

---

## 1. Por que isso existe

O comentário de vocês em [screen_bombas.h:13](matel-ivs-display-p4/main/screen_bombas.h:13)
estava certo e é a origem desta mudança:

> *"O lugar certo para esse contador é o iVS2008 (ou o CM06, que fica ligado
> com o barco parado); enquanto não existir lá, esta é a melhor aproximação
> honesta."*

Agora existe lá. Antes, o mesmo número era contado em três lugares e nenhum
via tudo:

| Onde | Perdia |
|---|---|
| Plataforma (`bilge.py`) | gap > 120 s = estado desconhecido; barco sem sinal não conta |
| Tela P4 (`screen_bombas.c`) | tudo o que acontece com a tela desligada |
| — | ninguém contava offline |

O módulo é a única coisa fisicamente ligada no DI. Vê toda borda, com ou sem
nuvem, com ou sem tela.

## 2. O contrato no fio

**`0x4D` broadcast (report)** — um canal por quadro, a cada 250 ms; varredura
completa das 12 DIs em 3 s. `destiny = 0xFF`, DLC 8:

| Byte | Campo |
|---|---|
| 0 | `sel << 4 \| canal` — canal 0..11; `sel` = 0 é o único layout hoje |
| 1..4 | `runtime_s` u32 LE — segundos acumulados em nível ativo |
| 5..7 | `cycles` u24 LE — partidas acumuladas (satura em `0xFFFFFF`) |

**`0x4D` endereçado ao nó (write)** — zera o horímetro de um canal. DLC 3:
`[canal, 0x5A, 0xA5]`. O magic não é enfeite: a operação é irreversível.

Exemplo real, DI3 com 300 s e 78 partidas:

```
prio=31 src=0x41 dst=0xFF cmd=0x4D  [02 2C 01 00 00 4E 00 00]
ID no fio: 0x1FFF414D
```

### ⚠️ Três coisas que mudam o desenho da tela

**a) Os totais são CUMULATIVOS e nunca zeram.** Não é simplificação: o
iVS2008 **não tem relógio** — nada de RTC, nada de SNTP, só
`esp_timer_get_time()`. Ele não sabe que horas são nem que dia é, então não
tem como fatiar em "últimas 24 h". Ele mantém um **odômetro**.

Quem tem relógio é a tela (NTP pelo WiFi). O "24 h" da página passa a ser
**diferença entre duas leituras**: guardem o par (timestamp, runtime, cycles)
de 24 h atrás e subtraiam. É o mesmo padrão do hodômetro de carro.

**b) O módulo não sabe o que é uma bomba.** Ele conta as 12 DIs sem exceção e
sem configuração. Qual canal é bomba, e a vazão de cada uma, continua vindo da
plataforma (`di_role: "bilge_pump"` + `flow_rate`/`flow_unit`). **Volume não
vem no fio** — é `runtime × vazão`, e quem tem a vazão faz a conta. Vocês já
recebem a vazão, então a multiplicação é de vocês.

De brinde: horímetro em toda entrada digital, não só nas bombas. Serve para
motor, gerador, o que estiver ligado ali.

**c) O contador não carrega estado instantâneo.** "Ligada agora" continua
vindo do `di_mask` do `0x41`, como hoje. E "ligada continuamente há N min"
também: dá para derivar de `runtime_s` + a borda do `di_mask`, mas uma tela
que acabou de bootar no meio de um ciclo não sabe quando ele começou. Se isso
incomodar, o nibble `sel` está reservado justamente para acrescentar um campo
`run_s` sem quebrar o layout — falem que eu faço no firmware do módulo.

## 3. O que muda no `screen_bombas.c`

1. Decodificar `0x4D` no `can_mtcp.c` de vocês (o `MTCP_CMD_*` novo).
2. Trocar a contagem própria por borda de subida pela leitura do módulo.
3. Guardar na NVS o **par de referência** (timestamp + runtime + cycles) em
   vez do acumulado próprio — é o que permite a janela de 24 h.
4. Tratar **reset**: se `runtime_s` vier MENOR que a referência, o horímetro
   foi zerado (troca de bomba, ou o módulo perdeu a NVS). A diferença correta
   nesse caso é o valor novo, não a subtração — que daria negativo.
5. O texto "contando desde …" pode sair: a contagem agora é do módulo e não
   depende da tela estar ligada. Se quiserem manter uma ressalva honesta, a
   que sobra é *"o módulo só conta enquanto estiver energizado"*.

Alarme local continua de vocês, e agora com número melhor: os limiares
(`bilge_alarm`) já chegam pelo `/hmi/config`, e passam a ser avaliados contra
o horímetro do módulo em vez do que a tela contou.

## 4. Estado de cada peça

| Peça | Situação |
|---|---|
| Firmware iVS2008 (`~/CM2008`) | ✅ implementado, compila (IDF 5.2.1), **não testado em hardware ainda** |
| `can_tool.py` (bancada) | ✅ `counters` e `reset-counter`; codec validado sem hardware |
| Gateway CM06 | ✅ decodifica `0x4D`, sobe `MT2,<uin>,CNT,...` a cada 30 s |
| Plataforma | ✅ tabela `io_counters` (migração 080), endpoint e alarmes preferem o horímetro; testado no dev |
| **Tela P4** | ⬜ **vocês** |

## 5. ⚠️ O opcode `0x4D` é PROVISÓRIO

O registro canônico do MTCP (`~/Documents/marine/protocols/mtcp/MTCP.ods` +
`IVS2008_extensions.md`) **não estava acessível** quando isto foi escrito, e
os `docs/` do CM2008 têm três alocações da faixa `0x4x` que se contradizem —
`mtnet_deck_control_spec.md` dá `0x45`/`0x46` a `THRS`/`ANCC`, que o firmware
usa para address-claim desde `6d256e6`. `0x48` foi a primeira escolha e
colidiria com `function_command` do plano de deck-control.

`0x4D` é o primeiro valor livre de toda reivindicação visível. Se o registro
disser outra coisa, muda em quatro lugares: `~/CM2008/firmware/main/types.h`,
`tests/can_tool.py`, `matel-ivs-gateway-fw/main/can_mtcp.h` e o de vocês.
Vale conferir antes de gravar firmware em barco de cliente.
