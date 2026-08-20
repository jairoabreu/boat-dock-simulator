# CAN / MTCP — o que este painel transmite e por quê

Doc de referência para agentes. Tudo aqui foi lido de `src/communicator/` e
`src/hal/mcp2515.h` — nenhuma afirmação vem do spec, só do código desta placa.
Spec canônico do MTCP (outro repo): `cm01/doc/mtcp_protocol.md`.

Arquivos que importam:

| Arquivo | Papel |
|---|---|
| `src/communicator/network.h` | vocabulário do barramento (endereços, comandos, prioridades) |
| `src/communicator/communicator.cpp` | **toda** a lógica de TX/RX |
| `src/communicator/vessel.h` | estado por motor (timers, flags de arbitragem) |
| `src/hal/mcp2515.h` | driver do controlador CAN (polled, sem IRQ) |

## 1. Papel deste nó

É um **painel de start/stop**: dois botões por motor (start e stop), dois motores,
quatro dígitos de 7 segmentos. Não decide nada sobre o motor — só publica o estado
dos botões e mostra o que o ECU responde.

| Endereço | Valor | Relação |
|---|---|---|
| `Self` | `0x30` | este painel (fonte de todo frame transmitido) |
| `CM03_PORT` | `0x11` | ECU do motor 1 (`vessel.engine_1.destiny`) |
| `CM03_STAR` | `0x12` | ECU do motor 2 (`vessel.engine_2.destiny`) |
| `CM06_4G` | `0x31` | gateway 4G — só escutado, nunca endereçado |
| `Broadcast` | `0xFF` | definido, **não usado** |

Comandos (`Network::Commands`): `BlockStatusRequest = 0x03` (só RX),
`EngineStarterState = 0x21` (só RX), `EngineStarterRequest = 0x22` (TX; também
observado em RX para arbitragem).

## 2. Camada física

MCP2515 externo no SPI1 (9 MHz), **250 kbps**, fixado no construtor do driver
(`src/hal/mcp2515.h:886`: `reset()` → `setCANSpeed(Can250KBPS)` → modo `Normal`).
Os CNF assumem cristal de 8 MHz no MCP2515.

- Todo frame transmitido é **extended** (29 bits), `msg.extended = true`.
- Filtros e máscaras são zerados no `reset()` com RXM em "receive any"
  (`src/hal/mcp2515.h:568-608`) → **o painel recebe tudo que passa no barramento**;
  a filtragem é 100% em software no `interpreter()`.
- `receive()` drena **um único frame por chamada** (RX0, senão RX1 —
  `src/hal/mcp2515.h:817`). Como `Communicator::run()` roda a cada 5 ms, o teto de
  consumo é ~200 frames/s.
- `transmit()` enfileira em TX0/TX1/TX2 e retorna "enfileirado", **não** "entregue"
  (comentário em `src/hal/mcp2515.h:800`). O retorno é ignorado no `Communicator`:
  não há retry, ack nem contagem de erro.

## 3. Layout do identificador

29 bits montados em `communicator.cpp:161-164`, decodificados em `:34-39`:

```
bits 31..24        23..16          15..8          7..0
[  priority  ] [ destination ] [   source   ] [  command  ]
```

```c
msg.identifier = prio << 24 | destiny << 16 | SOURCE << 8 | CMD;
```

Prioridade é o byte mais significativo, então **menor valor ganha a arbitragem CAN**:

| `Network::Priority` | Valor | Uso neste painel |
|---|---|---|
| `Highest` | `0b00000` (0x00) | botão pressionado |
| `High` | `0b00011` | definido, não usado |
| `Normal` | `0b00111` | definido, não usado |
| `Low` | `0b11111` (0x1F) | heartbeat com botões soltos |

Exemplo real, start do motor 1 pressionado: `0x00` `0x11` `0x30` `0x22` →
identifier `0x00113022`. Mesmo motor em repouso: `0x1F113022`.

## 4. O único frame transmitido

Sempre `EngineStarterRequest` (0x22), um por motor, nunca broadcast.

| Campo | Valor |
|---|---|
| identifier | `prio<<24 \| destiny<<16 \| 0x30<<8 \| 0x22` |
| extended | `true` |
| dlc | `4` |
| data[0] | `stop_cmd << 4 \| start_cmd` |
| data[1..3] | **sempre 0** (o DLC 4 é maior que o payload real) |

Cada nibble carrega o estado de um botão, não um pulso:

| Nibble | Significado |
|---|---|
| `0x7` | botão pressionado |
| `0x3` | botão solto |

| `data[0]` | Situação |
|---|---|
| `0x33` | ocioso (heartbeat) |
| `0x37` | **start pressionado** |
| `0x73` | stop pressionado |
| `0x77` | ambos pressionados (não é bloqueado no painel — quem resolve é o ECU) |

## 5. Lógica de ligar o motor (o caminho completo)

O comando é **por nível, não por borda**. O painel não "manda ligar" uma vez: ele
republica o estado dos botões enquanto estiverem pressionados. Segurar o botão é o
que mantém a partida — quem implementa a máquina de partida é o CM03.

Sequência a partir do aperto de `E1_Start` (PC13, pull-down, ativo em nível alto):

1. `run()` roda a cada 5 ms → `interpreter()` e depois `transmitMessages()`
   (`communicator.cpp:176`).
2. `transmitMessages()` lê os dois botões do motor por `DigitalIO::readState`
   (`:124-127`) → `start_cmd = 0x7`, `stop_cmd = 0x3`.
3. `requested = true` (algum nibble é 0x7) → `prio = Highest`, `rate = Fast`
   (100 ms). Sem botão: `prio = Low`, `rate = Slow` (250 ms).
4. Como a prioridade mudou de `Low` para `Highest`, `changed_prio` é verdadeiro e o
   frame sai **no mesmo ciclo de 5 ms**, sem esperar o período (`:140-145`). O
   mesmo vale ao soltar o botão: volta a `Low` e transmite na hora.
5. Passa pelos portões de bloqueio (seção 6) e transmite `data[0] = 0x37` a cada
   100 ms enquanto o botão estiver pressionado.
6. O CM03 responde `EngineStarterState` (0x21). O `interpreter()` marca
   `last_receive`, libera `can_send` e traduz o estado (`:104-107`).
7. `Display::update()` (100 ms) mostra animação `Start` durante `TurningOn` e `ON`
   quando o ECU reporta motor ligado.

Parar é simétrico: `E1_Stop` → `data[0] = 0x73` → `TurningOff` → `OF`.

## 6. Portões de transmissão (ordem exata, `communicator.cpp:111-174`)

Um `continue` em qualquer ponto significa: nenhum frame para aquele motor neste ciclo.

| # | Condição de bloqueio | Motivo |
|---|---|---|
| 0 | `!valid_network()` | bloqueia **os dois motores** (seção 8) |
| 1 | `!its_time && !changed_prio` | limita a taxa (100 ms pressionado / 250 ms ocioso) |
| 2 | `!engine->can_send` | outro mestre assumiu este ECU |
| 3 | `now - last_high_prio <= 250 ms` | janela de recuo após um comando alheio |

## 7. Frames recebidos e como são interpretados

`interpreter()` (`communicator.cpp:26-109`) trata um frame por ciclo:

**`BlockStatusRequest` (0x03) vindo de `CM06_4G`** → `vessel.cm06_communicating = true`.
É o único uso: prova de que a rede existe. Não olha destino nem payload.

**`EngineStarterState` (0x21) vindo de `engine->destiny`** → atualiza aquele motor:

| Byte | Campo |
|---|---|
| `data[0] & 0x0F == 0x07` | ligando → `TurningOn` |
| `data[0] >> 4 == 0x07` | desligando → `TurningOff` |
| `data[1]` | `Vessel::EngineException` (`GearEngaged` 0x01, `ThrottleOutOfPosition` 0x02, `ImproperStartup` 0x04, `Unmapped` 0x08, `EngineFault` 0xF0) |
| `data[2] & 0x01` | motor ligado → `On`, senão `Off` |

Transições têm precedência sobre o estado estável, porque o display de 7 segmentos
tem vocabulário limitado (comentário em `:53`).

**`EngineStarterRequest` (0x22) com prioridade `Highest` endereçado a um dos nossos
ECUs** — ou seja, outro comandante (CM01, joystick) mandando no mesmo motor:
`can_send = false` e `last_high_prio = now` (`:86-92`). O painel cede o barramento
e só volta a transmitir depois de ver um `EngineStarterState` daquele ECU
(`can_send = true`) **e** passados 250 ms do último comando alheio. É a arbitragem
multi-mestre — sem ela dois painéis brigariam pelo mesmo motor.

## 8. `valid_network()` — trava global de partida (`communicator.cpp:7-25`)

Verificação **só de energização**, com três caminhos:

1. `vessel.cm06_communicating` já verdadeiro → libera (uma vez validado, nunca invalida).
2. `E4_Stop` (PB0) em nível alto → libera e marca a flag. **Esse pino não é botão**:
   é um jumper de bypass para operar sem gateway 4G.
3. Senão libera enquanto `HAL_GetTick() < 3000` (janela de graça de boot).

Consequência: se nenhum CM06 aparecer e o jumper estiver aberto, **depois de 3 s o
painel para de transmitir para sempre** — botões deixam de ter efeito. `main.cpp`
ainda gasta 500 ms em `HAL_Delay` antes do loop, então a janela útil é ~2,5 s.

## 9. Timers e constantes

| Constante | Valor | Onde |
|---|---|---|
| `Period::Fast` | 100 ms | intervalo de TX com botão pressionado |
| `Period::Slow` | 250 ms | intervalo de TX ocioso; também a janela de recuo pós-arbitragem |
| `Period::Timeout` | 2000 ms | sem `State` do ECU → `LostComm` → `--` no display |
| `Period::NetworkValidation` | 3000 ms | janela de graça de boot |
| cadência do `run()` | 5 ms | `src/main.cpp` |

## 10. Comportamentos não óbvios (leia antes de mexer)

- **`LostComm` não dispara em barramento silencioso.** O teste de timeout está
  dentro do laço de motores que só é alcançado depois do `return` da linha `:47-51`,
  que exige um frame `0x21`/`0x22` já recebido. Se o barramento morrer por completo,
  o display congela no último estado em vez de mostrar `--`. Só entra em `LostComm`
  quando **algum** frame relevante chega (por exemplo do outro motor).
- **Os primeiros 250 ms de uptime não transmitem.** `last_high_prio` começa em 0 e o
  portão 3 é `now - 0 <= 250`.
- **O retorno de `transmit()` é descartado** e `last_transmission` é atualizado antes
  da chamada — um frame perdido por buffers cheios não é reenviado nem sinalizado.
- **`dlc = 4` com só `data[0]` preenchido.** Os três bytes de padding são zeros
  deliberados; o receptor não deve ler `data[1..3]`.
- **Um frame por ciclo de 5 ms na RX**, sem filtro de hardware: em barramento
  carregado, frames podem ser perdidos por overflow do RX do MCP2515.
- **`can_send` só volta a `true` ao receber um `EngineStarterState`** do ECU daquele
  motor. Se o outro mestre calar e o ECU parar de publicar estado, o painel fica
  permanentemente mudo para aquele motor.
- **E3/E4 existem no `pinout.h` e são inicializados**, mas `Vessel::MOTORS_NUMBER`
  é 2 — só E1/E2 geram tráfego; `E4_Stop` é o jumper da seção 8.

## 11. Contrato entre repositórios

O layout do identificador, `0x21`/`0x22` e a codificação `0x7`/`0x3` são
compartilhados com CM03 (ECU), CM06 (gateway) e os demais comandantes. Mudar
qualquer um destes quebra os outros repositórios silenciosamente — não há
negociação de versão no barramento:

- ordem dos campos no identificador;
- nibbles `0x7`/`0x3` em `data[0]`;
- significado de `data[1]` (exceções) e `data[2]` bit 0 (ligado/desligado);
- a regra de recuo por prioridade `Highest` (arbitragem multi-mestre).
