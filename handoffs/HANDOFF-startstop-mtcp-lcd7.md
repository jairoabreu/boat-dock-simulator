# Start/Stop de verdade no MFD iVS-LCD7 — o painel vira comandante MTCP

Handoff escrito em 19/08/2026 a partir de DUAS fontes que o Jairo entregou, e de
uma terceira que é o estado atual do repo:

| Fonte | O que é | Onde ficou |
|---|---|---|
| Planilha MTCP (Gabriel Novalski) | o **spec canônico** do barramento | `handoffs/mtcp/MTCP-planilha.md` |
| `can_protocol.md` | como o painel StartStop **de referência** se comporta, lido do código dele | `handoffs/mtcp/can_protocol-painel-startstop.md` |
| `matel-engine-panel` | o que a tela de 7" já tem | este repo |

O spec diz o que o fio aceita. O `can_protocol.md` diz o que já roda em campo — e
inclui os defeitos conhecidos daquele painel, que **não devem ser copiados**. Este
documento é a diferença entre os dois e o desenho para a tela.

## 1. O que a tela faz hoje

`ui_startstop.c` tem o gesto inteiro (arraste / segure / toque, gate de PIN por
piloto, re-trava por tempo) e ele termina em `engine_set_running(e, on)`, que
apenas **vira um bool local**. Nenhum quadro sai no barramento. `can_service.c`
já sobe um TWAI (v2, com handle) a 250 kbps, mas só **escuta NMEA 2000** (PGN
127488/127489) para a telemetria.

Ou seja: falta o comandante. É isso que este trabalho entrega.

## 2. O quadro que precisa sair — ECUESR (22h)

Identificador de 29 bits, montado assim (planilha, aba *Identifiers*; idêntico ao
painel de referência):

```
bits 28..24    23..16       15..8      7..0
[ priority ] [ receiver ] [ sender ] [ command ]

id = prio << 24 | destino << 16 | ORIGEM << 8 | 0x22
```

Prioridade é o byte mais alto, então **menor valor vence a arbitragem**:
`Highest = 0b00000`, `High = 0b00011`, `Normal = 0b00111`, `Low = 0b11111`.

Endereços que importam: **CM03/CM250 PORT = 0x11** (bombordo) e **STARBOARD =
0x12** (boreste). `CM06 = 0x31`. `BROADCAST = 0xFF` (não usar).

**A ORIGEM desta tela é `0x70 + instância`** — a faixa `0x70`–`0x7F` foi atribuída
ao MFD iVS-LCD7 pelo Jairo em 19/08/2026, no mesmo padrão das outras famílias
(`CM01 = 2Xh`, `iVS-2008 = 4Xh`, `CM02 = 5Xh`). Tela única no barco = **`0x70`**.
⚠️ Essa faixa **ainda não está na planilha do Gabriel** — enquanto não estiver, é
acordo entre nós e não contrato do barramento; ver §8.1.

Payload — DLC 4, e só o byte 0 tem significado (os outros três são zero
deliberado; o receptor não deve lê-los):

| Campo | Bits | Valores |
|---|---|---|
| `Engine_Starter` | 0.0–0.3 | `0h` desabilita · `3h` sem demanda · `7h` **demandado** |
| `Engine_Cutoff`  | 0.4–0.7 | idem, para desligar |

Logo: `0x33` ocioso · `0x37` **partida pedida** · `0x73` corte pedido · `0x77` os
dois (o painel não bloqueia; quem resolve é o ECU). Qualquer outra combinação
**deve ser ignorada** pelo receptor.

Cadência do painel de referência: **100 ms** enquanto há demanda (prioridade
`Highest`), **250 ms** ocioso (prioridade `Low`), e o quadro sai **na hora** em
que a prioridade muda, sem esperar o período.

## 3. O quadro que chega — ECUESS (21h), do ECU, 500 ms

| Campo | Bits | Significado |
|---|---|---|
| `Engine_Starter` | 0.0–0.3 | `7h` = ligando |
| `Engine_Cutoff` | 0.4–0.7 | `7h` = desligando |
| `Exception` | 1.0–1.7 | `00h` nenhum · `01h` **marcha engatada** · `02h` **acelerador fora de zero** · `04h` partida imprópria · `08h` erro não mapeado do ECU · `F0h` falha de motor (ver DTC) |
| `Engine_Status` | 2.0 | `0` motor provavelmente **desligado** · `1` provavelmente **ligado** |

O byte de exceção é o presente que este trabalho dá ao operador: hoje, se a
partida não acontece, a tela não diz por quê. Com ele, ela diz **"marcha
engatada"** ou **"acelerador fora de zero"** — que é a diferença entre um painel
que informa e um botão que não funciona.

## 4. NÍVEL, NÃO BORDA — e é aqui que a tela DIVERGE do painel de referência

O painel físico republica o estado do botão enquanto o dedo está nele: segurar é
o que mantém a partida, e quem implementa a máquina de partida é o CM03. **A tela
de 7" não tem botão físico** — o gesto (arrastar/segurar/tocar) termina e o dedo
sai.

Então a tradução tem de ser desenhada, e é a decisão central deste cartão:

- **Recomendado**: ao confirmar o gesto, a tela entra em *demanda* (`0x37`) e a
  mantém a 100 ms **até o primeiro de**: `Engine_Status = 1` (pegou), `Exception
  != 0` (o ECU recusou e disse por quê), ou um **teto de tempo** — sugestão de
  5 a 8 s, que é a ordem de grandeza de uma partida, a confirmar com o Gabriel.
  Ao terminar, volta a `0x33`. Um **CANCELAR** visível durante a demanda é
  obrigatório: partida em curso sem como abortar é pior que gesto difícil.
- A alternativa (mapear "SEGURE PARA LIGAR" para o dedo literalmente no vidro)
  fica registrada, mas tem um problema: o gesto de segurar da tela já tem outro
  significado (confirmação), e o operador tirar o dedo no meio da partida
  cancelaria o motor pegando.

Qualquer que seja a escolha, ela vai no resultado com o porquê.

## 5. Arbitragem multi-mestre — obrigatória, não é enfeite

Outro comandante (CM01, joystick, o painel físico) pode mandar no mesmo ECU. A
regra que o painel de referência implementa, e que a tela precisa repetir:

Ao ver um **ECUESR (22h) com prioridade `Highest`** endereçado a um dos nossos
ECUs vindo de **outra origem**: parar de transmitir para aquele motor e marcar o
instante. Só voltar depois de ver um **ECUESS daquele ECU** *e* passados **250 ms**
do último comando alheio.

Sem isso, dois comandantes brigam pelo mesmo motor. **Com isso**, vale a ressalva
do painel de referência: se o outro mestre calar e o ECU parar de publicar
estado, o painel fica mudo para sempre naquele motor — a tela deve tratar esse
caso em vez de herdá-lo (ver §7).

## 6. Identificação no barramento — SEN (00h)

O spec é explícito: *"todos os dispositivos devem enviar esta mensagem de
identificação ao entrar no barramento; sempre que um novo dispositivo for
detectado, todos devem se identificar de novo"*. O painel de referência **não faz
isso** — é lacuna dele, não permissão.

`Device_Code` (bytes 0–1) tem uma entrada que parece ser exatamente este produto,
criada em 19/08/2026: **`0707h` = CM07D (Digital/tela)** (e `0701h` = CM07B,
botão). **Confirmar com o Gabriel antes de gravar no fio.**

## 7. Os defeitos do painel de referência que NÃO devem ser copiados

O `can_protocol.md` é honesto sobre eles (seção 10). Ficam aqui como lista de
"não repita":

1. **Trava de rede permanente.** Lá, se nenhum CM06 aparecer em ~2,5 s de boot e
   o jumper de bypass estiver aberto, o painel **para de transmitir para sempre**
   — botões deixam de ter efeito, sem aviso. Se a tela adotar qualquer trava
   dessas, ela tem de ser **revalidável** e **dizer na cara** por que não vai
   comandar. Painel que não explica silêncio é o pior defeito de todos.
2. **`LostComm` que não dispara em barramento morto** — lá o teste de tempo vive
   depois de um `return` que exige um quadro já recebido. Na tela, ausência de
   ECUESS por 2 s **é** perda de comunicação, com barramento silencioso ou não.
3. **Retorno do `transmit()` descartado**, sem retry nem contagem. A tela já
   aprendeu essa lição no iVS2008 (escrita single-shot precisa de confirmação por
   estado); aqui vale o mesmo princípio — e o `Engine_Status`/`Exception` são a
   confirmação natural.
4. **Um quadro por ciclo na RX, sem filtro de hardware.** Drenar o RX em laço até
   esvaziar, não um por vez.

## 8. O que precisa ser decidido antes de gravar no fio (perguntas ao Gabriel)

1. ~~Qual endereço a tela usa?~~ **RESPONDIDO (Jairo, 19/08/2026): faixa `0x70`–
   `0x7F`, tela única = `0x70`.** Resolve a colisão com o painel físico, que fica
   em `0x30`. **Pendência que sobra e é do Jairo, não do firmware**: levar a faixa
   para a planilha canônica do Gabriel. Endereço que só existe no nosso handoff é
   endereço que o próximo dispositivo vai ocupar sem saber — foi exatamente assim
   que `0x30` acabou compartilhado entre o StartStop e o IVS-4180.
2. **Device_Code é mesmo `0707h`?**
3. **Teto de tempo da demanda de partida** (§4) — 5 s? 8 s? O CM03 tem limite
   próprio?
4. **O MFD deve respeitar alguma trava de rede** (o papel do CM06 lá), ou comanda
   assim que o ECU responde?

## 9. Hardware — o que conferir ANTES de escrever código

- O P4 tem **3 controladores TWAI**; o `can_service.c` usa o 0 com a API **v2**
  (handle). O segundo barramento **tem de** usar outro controlador e outro handle,
  na mesma API, para os dois coexistirem.
- ⚠️ **Divergência de pinos a resolver no banco**: o cabeçalho do
  `can_service.h` diz N2K em **TX=45/RX=46**, e o registro de arquitetura da
  família diz N2K em **46/47** com **45/46 reservados para o MTNet**. Medir a
  fiação antes de assumir.
- ⚠️ **GPIO1 é do oscilador RTC** no esquemático da 7" — não usar.
- Transceiver do MTNet: SN65HVD230/232 (3,3 V, liga direto no P4). Terminação de
  120 Ω só nas **duas pontas** do barramento — muitos módulos trazem o resistor
  embarcado; se a tela não for ponta, remover.

## 10. Regras da casa que valem aqui

Nada de `lv_anim` infinita; repintar só o que muda (assinatura/`pin_*`) — o
`full-refresh` desta placa transforma repintura boba em touch lento; a task de
CAN não desenha, e o desenho não bloqueia a CAN. E o de sempre: **a tela não
mente** — enquanto não houver ECUESS, o estado do motor é *desconhecido*, não
*desligado*.
