# Diagnóstico — plataforma não aciona as saídas do iVS2008

**Data:** 01/08/2026 · **Bancada:** 1× DOT460 + 1× CM06 + 1× iVS2008 + tela 10.1"
**Sintoma:** acionar uma saída pela plataforma web não movia o relé. Pela tela, movia.

## ✅ RESOLVIDO — pino de RX da RS232 errado no firmware do CM06

**Causa:** `DOT_RX_GPIO` apontava para o **GPIO3**, que no CM06 **não está
conectado a nada**. O RX real é o **GPIO5**.

Pinout correto, do esquemático (`Schema.pdf`):

| Folha | Evidência |
|---|---|
| 5 (RS232) | U7/MAX3232 pino 10 = `DIN2` ← net **`RS232 TXD`** (entrada do driver = TX do MCU) |
| 5 (RS232) | U7/MAX3232 pino 9 = `ROUT2` → net **`RS232 RXD`** (saída do receptor = RX do MCU) |
| 1 (MCU) | pino 9 = **GPIO4** = `RS232 TXD` · pino 10 = **GPIO5** = `RS232 RXD` |
| 1 (MCU) | pino 8 = **GPIO3** marcado como **não conectado** |

```c
#define DOT_TX_GPIO   4        /* pino 9  = net "RS232 TXD" -> U7 DIN2  */
#define DOT_RX_GPIO   5        /* pino 10 = net "RS232 RXD" <- U7 ROUT2 */
```

Com o RX correto, a descida completa apareceu no log em um único teste:

```
RS232 RX 32 bytes: 44 4F 54 32 33 32 7C 53 56 52 7C 49 56 53 2C 53 45 54 2C 34 31 2C 32 2C 31 ...
                   D  O  T  2  3  2  |  S  V  R  |  I  V  S  ,  S  E  T  ,  4  1  ,  2  ,  1
can: write node=0x41 set=0x0004 state=0x0004
ser: IVS,SET node=0x41->0x41 ch=2 st=1
ser: TX IVS,INFO node=0x41 DO=04       <- o módulo aplicou
```

`DO` acompanhou os comandos: `01 → 00 → 04 → 00`. Antes ficava travado em `00`.

## Onde a investigação se perdeu (para não repetir)

1. O comentário do cabeçalho do `serial_dot.c` dizia `GPIO3(TX)/GPIO4(RX)` — errado
   nos dois. Foi tratado como fonte confiável **sem conferir o esquemático**.
2. Ao "corrigir" a divergência, o RX foi movido de 5 (correto) para 3 (pino solto),
   e o **dump raw da RS232 entrou no mesmo commit** — então ele nunca rodou no pino
   certo. Os "zero bytes" resultantes foram tratados como prova de que o rastreador
   não transmitia.
3. A varredura de bordas mostrou `GPIO5=2..10` e isso foi descartado como ruído.
   Era o RX de verdade.
4. Hipóteses caras (CAN TX mudo, `APP_TWAI_LBK_GPIO`, fiação, configuração do
   DOT460) foram levantadas a partir de uma medição contaminada.

**Lição:** conferir o esquemático antes de qualquer teoria sobre pino. A leitura
do PDF levou dois minutos e respondeu o que horas de instrumentação não responderam.

## Correções que ficam no firmware

- Pinout documentado com a referência de folha/pino do esquemático.
- Dump raw da RS232 em hex, em nível `DEBUG` (o doc do protocolo prometia e não existia).
- `twai_transmit` com log de falha — antes um bus-off era indistinguível de sucesso.
- Comandos de configuração do CM06: `PING`, `GET_VERSION`, `GET_SERIAL`, `REQ_STATUS`.

## Correções na plataforma (01/08)

- **Correlação resposta→comando** pelo counter, marcando `acked` com o frame de
  resposta. Antes o comando ficava eternamente em `sent`.
  (`matel-gateway/internal/protocols/dot460/pending.go`)
- **Realinhamento de endereço**: 19 canais movidos de `0x40` para `0x41`, duplicação
  em dois nós resolvida, módulo cadastrado com o serial `2606200005`.
