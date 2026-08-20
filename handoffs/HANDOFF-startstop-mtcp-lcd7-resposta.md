# Resposta — Start/Stop de verdade no MFD iVS-LCD7 (comandante MTCP)

Resposta ao `HANDOFF-startstop-mtcp-lcd7.md`, escrita em 19/08/2026 depois de
implementar o comandante no `matel-engine-panel`. Demanda #270 do quadro 18.

**Estado: implementado inteiro e provado em simulação; ainda não ligado no fio.**
Todo o contrato do §8 foi seguido como está lá (endereço `0x70`, Device_Code
`0707h`, dedo no vidro sem teto de tempo, trava de rede respeitada). O código
compila nas duas placas, mas nasce **desabilitado** (`CONFIG_MFD_MTNET_ENABLE=n`)
por **um único motivo, que é de hardware e não de protocolo**: os pinos do §9.
Medida a fiação, é um Kconfig e o comando sai no barramento.

## O que foi feito

| Arquivo | Papel |
|---|---|
| `main/mtcp_core.{c,h}` | o protocolo e as decisões, **sem uma linha de ESP-IDF** |
| `main/mtcp_service.{c,h}` | o segundo TWAI, a task de 10 ms, a ponte com a UI |
| `tools/mtcp_test.c` | banco de provas do núcleo, roda no PC |
| `main/ui_startstop.c` | o gesto virou demanda; a tela mostra a resposta do ECU |

A separação não é enfeite: sem CM03 na bancada, é o `mtcp_core.c` — o **mesmo
arquivo** que o firmware compila — que roda no PC contra um ECU de mentira e um
relógio falso. **73 verificações, 0 falhas.**

```sh
cc -std=c11 -Wall -Wextra -Imain main/mtcp_core.c tools/mtcp_test.c -o /tmp/mtcp_test && /tmp/mtcp_test
```

## §4 — o dedo no vidro É o botão

Implementado como decidido. Os **três estilos continuam valendo** e todos são
gestos sustentados; muda só **quando a demanda nasce**:

| Estilo | A demanda nasce… | …e morre |
|---|---|---|
| Botão simples | no `PRESSED`, na hora, sem confirmação | ao soltar |
| Slider | quando o arraste passa de 82% **com o dedo ainda no controle** (no `PRESSING`, não no `RELEASED`) | ao soltar |
| Aperta e segura | quando a barrinha enche — e ela só enche com o dedo no vidro | ao soltar |

`RELEASED`/`PRESS_LOST` devolve `0x33` com prioridade `Low` **no mesmo ciclo**,
nos três. Nos estilos 2 e 3, gesto que completa com o dedo já fora não gera
demanda nenhuma — a demanda nasce em eventos que só existem com o dedo presente.

Duas consequências que valem registrar, porque são o oposto do que o cartão
original pedia:

- **A tela não desiste sozinha.** Se o motor pegar com o dedo ainda no vidro,
  ela continua publicando `0x37` — quem faz a máquina de partida é o CM03.
  Não há teto de tempo, não há contagem regressiva, não há CANCELAR (o cancelar
  é tirar o dedo). Está no teste 3, com esse nome.
- **A recusa também não tira o dedo.** O ECU dizer "marcha engatada" mostra o
  recado, mas não interrompe a demanda: quem decide soltar é o operador.

Os rótulos passaram a dizer `ARRASTE E SEGURE P/ LIGAR` / `SEGURE PARA LIGAR` —
o antigo "TOQUE PARA LIGAR" prometia um toque instantâneo que nunca existiu.

**O gate de PIN interrompe o dedo** (⚠️ do §4): ao fechar o teclado a mão não
está mais no controle. A tela diz `SENHA OK - REFACA O GESTO`, em vez de deixar
parecer que a partida falhou.

## §3 — o presente: a tela diz POR QUÊ

| Exceção | O que aparece |
|---|---|
| `01h` | `RECUSADO: MARCHA ENGATADA` |
| `02h` | `RECUSADO: ACELERADOR FORA DE ZERO` |
| `04h` | `RECUSADO: PARTIDA IMPROPRIA` |
| `08h` | `RECUSADO: ERRO DO ECU` |
| `F0h` | `RECUSADO: FALHA DE MOTOR` |

Com bip de aviso, sumindo sozinho em 8 s. Detalhe de implementação que importa:
a faixa **não é clicável de propósito** — o LVGL só roteia toque para objeto
clicável, então ela pode aparecer com o dedo no vidro sem roubar o toque e sem
matar a demanda que aquele dedo está sustentando.

O ECU repete o ECUESS a 500 ms; só exceção **nova** (ou motivo diferente) vira
recado, senão seria uma metralhadora. Recusa que chega com o painel coberto por
um menu é consumida em silêncio: recado de partida só vale contemporâneo.

E a regra da casa: **a tela não mente** — sem ECUESS o chip diz `SEM ECU`, não
`DESLIGADO`. Com elo, quem manda no estado é o `Engine_Status`, não mais o bool
local.

## §7.1 — a trava de rede: respeitada, revalidável, e sempre explicada

O MFD respeita a trava, como decidido: sem nenhum quadro do CM06 (`0x31`) no
barramento, o gesto **não vira comando**. O que não se copiou foi a forma:

- **Revalidável**: o CM06 pode aparecer no minuto 10 e libera na hora — inclusive
  com o dedo já no vidro, que passa a comandar sem precisar refazer o gesto
  (está no teste 5).
- **Falante**: enquanto travada, o próprio slider diz `SEM REDE - NAO COMANDA`,
  em cinza, no lugar de "ARRASTE PARA LIGAR". Nada de botão que vira enfeite em
  silêncio.
- Travada, a tela **segue presente** no barramento com `0x33` — que é "sem
  demanda", não comando.
- Uma vez provada, não invalida: derrubar o comando no meio da operação porque o
  gateway piscou seria pior que a doença.
- `MFD_MTNET_REQUIRE_CM06` desliga a trava só para bancada sem gateway.

## §5 — arbitragem, implementada inteira

Ver ECUESR `Highest` para um dos nossos ECUs vindo de outra origem: a tela cala
**naquele motor** (o outro segue normal), e só volta depois de ver um ECUESS
daquele ECU **e** passarem 250 ms. Enquanto isso o slider diz
`OUTRO COMANDO NESTE MOTOR`. O eco do nosso próprio quadro é ignorado pela
origem — senão a tela se calaria sozinha.

## §7 — os quatro defeitos, um por um

1. **Trava permanente e muda: não herdada.** Além do que está acima, a mordaça
   da arbitragem **expira sozinha** em 2 s sem nenhum comando alheio, em vez de
   esperar para sempre por um ECUESS que pode nunca vir. O caso está no banco de
   provas com o nome que merece: *"MUDO PARA SEMPRE — o defeito §7.1 foi
   herdado"*.
2. **LostComm em barramento morto: corrigido.** O teste é
   `ess_seen && (agora - t_ess) < 2 s`, avaliado no passo periódico, fora de
   qualquer caminho que dependa de ter chegado quadro (teste 7).
3. **Retorno do transmit: nunca descartado.** Só o quadro **confirmado** anda com
   o relógio da cadência; o negado é reenviado no passo seguinte, com piso de
   20 ms para não martelar barramento morto, e é contado. O driver está com
   alertas ligados: `TX_FAILED` (saiu da fila mas não foi entregue) marca
   reenvio, e `BUS_OFF` dispara recuperação com log.
4. **RX drenada em laço** até esvaziar (teto de 64 por ciclo), fila de 48, a cada
   10 ms.

## §6 — SEN (00h): implementado e LIGADO

Com o Device_Code confirmado (`0707h`, CM07D), a tela se apresenta ao entrar no
barramento e se reapresenta quando vê o SEN de outro dispositivo, limitado a 1/s
para não virar tempestade. Série vai como "Unavailable" — a tela ainda não tem
número de série no barramento; se isso for necessário, é o próximo passo.

## §9 — hardware: a divergência é real e continua aberta

Conferido no código, não no fio: o `can_service.c` usa **TX=46 / RX=47** para o
N2K. O comentário do `can_service.h` dizia 45/46 — **estava errado, foi
corrigido**, e os pinos agora são `#define` no cabeçalho, fonte única da verdade.

Com isso, a reserva de **45/46 para o MTNet** colide com o N2K no **GPIO46**. Um
dos dois registros está errado e só medindo se sabe qual. O firmware não finge
que sabe: se os pinos configurados baterem com os do N2K, o serviço **recusa
subir e diz exatamente isso no log**, em vez de brigar pelo pino:

```
E (xxx) mtcp: MTNet TX=45 RX=46 COLIDE com o N2K (TX=46 RX=47):
              meça a fiação e ajuste MFD_MTNET_TX/RX_GPIO. MTNet NAO subiu.
```

GPIO1 (oscilador RTC) também é recusado. Controlador TWAI 1 (o 0 é do N2K), API
v2 com handle, 250 kbps.

## O que ficou por provar

Camada física, os pinos de verdade, a terminação de 120 Ω, a temporização real
do TWAI e a resposta de um CM03 verdadeiro. Nesta sessão não havia **nenhuma**
tela no USB, então nem o build foi ao hardware. **Não vai a barco sem um CM03
real na bancada primeiro.**

## O único pendente

**Medir a fiação do MTNet** e ajustar `MFD_MTNET_TX_GPIO` /
`MFD_MTNET_RX_GPIO`. Feito isso, `MFD_MTNET_ENABLE=y` e a tela comanda.
Nenhuma pergunta de protocolo ficou em aberto.
