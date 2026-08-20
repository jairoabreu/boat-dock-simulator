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

## 4. NÍVEL, NÃO BORDA — o dedo no vidro É o botão

**DECIDIDO (Jairo, 19/08/2026): enquanto o dedo permanecer no slider, a tela
mantém a demanda; tirou o dedo, para de mandar.** É o mesmo contrato do painel
físico, com o vidro no lugar da tecla — e é a escolha mais segura das que
estavam na mesa, porque devolve ao operador o *homem-morto*: a partida só
continua enquanto alguém está com a mão nela.

Na prática, para o firmware:

- Gesto confirmado **e dedo ainda no slider** → `0x37` (partida) ou `0x73`
  (corte), prioridade `Highest`, republicando a **100 ms**.
- `LV_EVENT_RELEASED` / `PRESS_LOST` → volta a `0x33` **no mesmo ciclo**,
  prioridade `Low`, 250 ms. Soltar não é "cancelar o comando": é parar de pedir,
  que é o que o ECU espera.
- Quem faz a máquina de partida continua sendo o CM03. A tela não conta tempo de
  motor de arranque nem decide quando desistir.

⚠️ **CONSEQUÊNCIA QUE PRECISA DE DECISÃO PEQUENA — o estilo TOQUE.** Os Ajustes
oferecem três estilos de acionamento (arrastar / segurar / tocar). Com a regra
acima, *arrastar* e *segurar* funcionam sozinhos (o dedo termina o gesto em cima
do controle e só precisa ficar lá), mas **um toque não tem duração**: não há
como sustentar demanda nenhuma com ele. Proposta a confirmar no resultado: para
LIGAR, o estilo *tocar* deixa de ser oferecido (ou cai para *segurar*), com o
texto dizendo por quê. Oferecer um gesto que não consegue dar partida é pior que
não oferecer.

⚠️ **O gate de PIN interrompe o dedo.** Hoje o slider travado abre o teclado; ao
fechar, o dedo não está mais no controle. Depois de liberar, o operador
**refaz** o gesto — e a tela precisa deixar isso claro em vez de parecer que a
partida falhou.

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

`Device_Code` (bytes 0–1) = **`0707h` (CM07D, Digital/tela)** — **CONFIRMADO
pelo Jairo em 19/08/2026**; `0701h` é o CM07B (botão), outro produto. A tela
**deve** mandar o SEN ao entrar no barramento e sempre que detectar um
dispositivo novo, como o spec manda — o painel de referência não faz, e isso é
lacuna dele.

## 7. Os defeitos do painel de referência que NÃO devem ser copiados

O `can_protocol.md` é honesto sobre eles (seção 10). Ficam aqui como lista de
"não repita":

1. **Trava de rede permanente e MUDA.** O MFD **respeita a trava** (decisão do
   Jairo, 19/08 — ver §8.4): sem rede provada, não comanda. O que **não** se
   copia é a forma: lá, se nenhum CM06 aparecer em ~2,5 s de boot, o painel para
   de transmitir **para sempre e em silêncio**, e os botões viram enfeite. Aqui a
   trava tem de ser **revalidável** (o CM06 pode aparecer no minuto 10 — e aí
   libera) e **visível**: o slider mostra por que não vai comandar, no lugar de
   fingir que funciona. Painel que não explica o próprio silêncio é o pior
   defeito da lista.
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
2. ~~Device_Code é mesmo `0707h`?~~ **RESPONDIDO: sim, `0707h` (CM07D).**
3. ~~Teto de tempo da demanda de partida?~~ **NÃO EXISTE MAIS** — com a regra do
   §4 (dedo no vidro), quem limita é o operador, e a máquina de partida é do
   CM03. A tela não arbitra duração.
4. ~~O MFD respeita trava de rede?~~ **RESPONDIDO: sim, respeita** — mas na forma
   do §7.1: revalidável e dizendo por quê, nunca muda para sempre.

**Nada mais bloqueia a implementação.** O que sobra é de fora do firmware: levar
a faixa `0x70`–`0x7F` para a planilha canônica do Gabriel (§8.1).

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
