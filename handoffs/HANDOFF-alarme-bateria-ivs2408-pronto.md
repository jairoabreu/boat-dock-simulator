# Handoff — alarme de bateria: o módulo já grava, compara e avisa

**Data:** 08/08/2026 · **Origem:** cartão #174 (firmware do iVS-2408, quadro 11) ·
**Para:** plataforma web / API (cartão #173, quadro 29), gateway CM06
(cartão #175, quadro 9), `matel-gateway` (Go) e tela 10.1" (quadro 26)

**Resposta a** `HANDOFF-alarme-bateria-ivs2408.md` (§4) e a
`HANDOFF-alarme-bateria-cm06-pronto.md`.

> **Resumo em uma linha:** o `I2008AL` existe, roda em silício, e o bloqueio da
> cadeia saiu — mas **três coisas mudaram em relação à proposta**, e a primeira
> delas quebra o CM06 hoje: o byte `lado` do quadro de alarme não é 0/1.

---

## 1. O que mudou, e por quê

Três desvios do §4. Os dois primeiros são acréscimos; o terceiro é uma
correção que precisa de duas linhas do lado do CM06.

### 1.1 O `lado` do alarme: `0x01` lo, `0x02` hi, `0x03` **normal** — e `0x00` reservado

O §4 escreveu `[canal, lado, valor_mV]` sem dizer que números `lado` carrega. O
CM06 (#175) precisou escolher e escolheu `LO = 0`, `HI = 1`. O módulo escolheu
outra coisa, e a diferença **não** é gosto:

```
0x00  reservado, NUNCA emitido
0x01  LO      abaixo do mínimo
0x02  HI      acima do máximo
0x03  NORMAL  voltou para dentro da faixa
```

Dois motivos, nesta ordem de peso:

1. **`0x00` reservado é regra desta família de quadros desde o #141.** Com
   `LO = 0`, um quadro DLC 4 zerado por engano — FIFO suja, driver escrevendo
   curto, quadro truncado — decodifica como *"canal 0 cruzou o mínimo em 0 mV"*.
   Num alarme de bateria isso é exatamente o WhatsApp falso que o §9 do handoff
   original pediu para não existir. É a mesma razão de `nack::RESERVED` ser
   `0x00` e nunca sair.

2. **`normal` precisava caber.** É o acréscimo do item 1.2 abaixo, e não há
   valor com sentido para ele num par 0/1.

**O que o CM06 precisa mudar:** `CM_AL_LADO_LO` de `0` para `1`,
`CM_AL_LADO_HI` de `1` para `2`, e uma terceira constante para o `0x03`. Medido
aqui: com o mapa de hoje a cossimulação de vocês lê o `lo` do módulo como `hi`
e ignora o `hi` — ver §5.

### 1.2 O alarme também diz quando **acaba** (`SIDE=normal`)

Não estava na proposta, e sem isso o alarme entra e nunca sai: quem consome
fica com o canal preso em vermelho até alguém reiniciar alguma coisa. O
`cooldown_min` da plataforma governa a *repetição da notificação*, não o *fim da
condição* — são coisas diferentes e só o módulo sabe a segunda.

Sugestão de MT2, para o CM06 fechar sob o cartão dele:

```
alarme:  MT2,<uin>,EVT,<seq>,ALM=<ch>,SIDE=<lo|hi|normal>,MV=<mV>,NODE=<xx>
```

Consumidor que não conheça `normal` continua funcionando — só não limpa
sozinho.

### 1.3 O alarme ativo se **repete a cada 60 s**

Também não estava na proposta. Um evento só na transição é invisível para
qualquer coisa que chegue ao barramento *depois* dele: uma tela que reinicia, um
CM06 trocado, um laptop de bancada. O módulo é a única coisa que sabe o estado,
e não há consulta que o devolva (a consulta devolve a *configuração*).

Um quadro por canal em alarme por minuto não é enxurrada. **`normal` não se
repete** — só o alarme ativo. Do lado de vocês isso quer dizer que `ALM=` pode
chegar repetido com o mesmo `SIDE`; é atualização de estado, não evento novo, e
o `cooldown_min` continua governando a notificação ao usuário.

---

## 2. Os dois números que vocês pediram para ficarem escritos (§5 e §9)

Estão em `~/CM2008/Firmware/V5-rs/src/alarm.rs`, no cabeçalho, com a
justificativa inteira:

| | Valor | Por quê |
|---|---|---|
| Banda morta (`HYSTERESIS_MV`) | **300 mV de retorno** | o número que vocês sugeriram. Entra no limiar, só sai 0,3 V para dentro. Resolve a tensão parada em cima do limiar |
| Tempo mínimo do lado errado (`CONFIRM_MS`) | **3 s contínuos** | é o que uma partida de motor não sobrevive: o afundamento dura de meio segundo a dois. O ADC varre um canal por passada de 5 ms, então cada canal tem leitura nova a cada 40 ms e 3 s são ~75 amostras seguidas. Rápido perto do que uma bateria leva para descarregar |
| Canal sem fio (`NO_WIRE_MV`) | **500 mV no borne**, o número de vocês | abaixo disso o canal **congela**: não alarma *e não recupera*. Um fio que cai enquanto o banco está baixo não pode virar "voltou ao normal" — seria a mentira mais cara que o módulo poderia contar. Se mudar, muda em `battery_detector.py` e no `docs/MT2-alarme-bateria.md` do CM06 |

**Consequência prática do `CONFIRM_MS` para quem testa:** o alarme chega **3 s
depois** de a tensão cruzar. O `RESP_S = 3.0` da cossimulação de vocês está em
cima da linha — recomendo 5 s.

---

## 3. As recusas: dois motivos de `I2008NK` novos

Vocês pediram recusa explícita para canal ≥ 8, `min ≥ max` e limite acima do que
a entrada mede. Os três voltam como `I2008NK`, e como o CM06 (com razão) não
julga os dois últimos, eles precisam de motivo próprio:

| Situação | `reason` | `detail` |
|---|---|---|
| canal ≥ 8 | `0x02 FORA_DE_FAIXA` (já existia) | `8`, os canais que existem |
| `min ≥ max` | **`0x04 FAIXA_INVERTIDA`** (novo) | `0` — o que há a dizer já está no pedido |
| limite acima do que a entrada mede | **`0x05 ACIMA_DO_MEDIVEL`** (novo) | **`25`, o teto em VOLTS** |
| bit de flag desconhecido | `0x03 NAO_SUPORTADO` (já existia) | `0` |

O `detail = 25` é o mesmo desenho do teto de bobinas do #141/#159: o número
pertence a quem o aplica, e é assim que a web aprende um teto novo sem release
quando um lote futuro trouxer entrada de faixa maior. **Não cravem 25 no código
da nuvem.**

O byte 2 do `I2008NK` (`request`) carrega o **byte de flags** do pedido
recusado, para o `I2008AL`.

E o que vocês já sabem, repetido porque continua valendo: **ausência de
`I2008NK` não é sucesso**. O que fecha uma gravação é o `AL=` seguinte.

---

## 4. O resto do §4 saiu igual, sem uma vírgula de diferença

Confirmado campo a campo, em silício:

- os quatro quadros, com os DLCs propostos (escrita 7, consulta 1, relatório 6,
  alarme 4), distinguidos por DLC;
- **persistido em FRAM**, registro `"ALRM"` em `0x0600`, com número mágico,
  tamanho e CRC. Página nova depois do último registro — **não** colado ao
  `PULSE_ADDR`, porque registro novo entra depois do último e nunca no meio de
  um que já existe. O que o pedido quer dizer de verdade ("mora no módulo e
  sobrevive a troca de firmware") vale igual: a FRAM é peça externa no I2C e
  nada do caminho de gravação a toca;
- **milivolts inteiros de borne**, `u16`, sem conversão nenhuma no módulo;
- **`flags` liga cada limite**; limite desligado não é limite zero. Provado nos
  dois sentidos: um máximo de 0 V **ligado** alarma, os mesmos números com
  `flags = 0` são silêncio;
- **a trava `0x5A`**, e escrita sem ela é ignorada em silêncio;
- **o relatório é a única fonte do estado**: sai em difusão a cada escrita
  aceita e a cada consulta, **nunca periodicamente**. `can_tool.py` mexendo por
  fora aparece na consulta seguinte;
- consulta `0xFF` responde pelos **oito** canais — um relatório por passada de
  5 ms, porque a FIFO de transmissão do MCAN tem quatro vagas e oito quadros de
  uma vez perderiam metade em silêncio. Uma varredura completa leva ~40 ms;
- só canais 0–7;
- **nasce desligado** em todo canal.

Uma nota de ordem: a vigilância roda **fora** da guarda de endereço — um banco
descarregando não espera o nó resolver arbitragem. O que depende de endereço é
só o anúncio, porque um quadro saindo como `0xFD` não identifica placa nenhuma.

---

## 5. Como foi verificado

**Em silício, na placa real** (`./gravar.sh --bench`, `bench_protocol` passo 5,
08/08/2026). Passou: escrita e relatório campo a campo, a trava, as quatro
recusas com motivo e detalhe, a consulta de um canal e a de todos, a ida e volta
pela FRAM lida por instância nova, o cruzamento nos dois sentidos, a banda
morta segurando a volta, o afundamento de partida sendo engolido e a régua dos
0,5 V. A transcrição está em `~/CM2008/Firmware/V5-rs/README.md`.

**O que a bancada NÃO prova:** a leitura foi **ditada** por
`Analog::force_millivolts`, não veio de uma fonte no borne. O conversor tem
prova própria no `bench_analog`; o que fica sem prova de campo é a junção dos
dois — uma bateria de verdade cruzando um limiar de verdade. Precisa de uma
fonte de bancada descendo devagar; é meia hora e ninguém a fez ainda.

**Sem silício:** `~/CM2008/tools/alarme_sim.py`, 81 conferências sobre o
emulador real num barramento `virtual`. Não é vacuoso: tirar a banda morta
derruba 3 conferências, tirar a janela de confirmação derruba 8, tirar a régua
do canal sem fio derruba 2.

**E a cossimulação de vocês já enxerga o suporte nativo.** O
`tools/cosim/alarme_bateria_cosim.py` procura `CMD_ANALOG_ALARM` no
`can_node.py` a cada execução — o `can_node.py` agora o tem, então o substituto
saiu de cena sozinho e o teste virou cossimulação inteira. Rodada aqui,
08/08/2026, com o gateway de verdade:

```
# o emulador implementa o 0x4B — cossimulação INTEIRA
...
  [FAIL] alarme lo: obtido 'ALM=2,SIDE=hi,...', esperado 'ALM=2,SIDE=lo,...'
  [FAIL] alarme hi: obtido '(sem alarme)', ...
AttributeError: 'Node' object has no attribute 'al'
```

As duas falhas são o §1.1 — o `lo` do módulo lido como `hi`, e o `hi` ignorado
por não existir no mapa de vocês. **É esta a mudança que desbloqueia a
cossimulação inteira**, e é de duas linhas.

O `AttributeError` é do passo 8 (*"configuração mexida por fora"*), que alcança
o atributo do substituto. No emulador de verdade os nomes são:

```python
node.alarm[ch]        # {"flags": int, "min_mv": int, "max_mv": int}
node.alarm_side[ch]   # 1 lo / 2 hi / 3 normal
```

E não há `node.al_vigiar()`: a vigilância roda dentro de `node.tick()`, como no
firmware. Se precisarem apertar as janelas de tempo num teste,
`Node(args, bus)` aceita `args.alarm_confirm_s` e `args.alarm_repeat_s` — é o
mesmo truque do `coil_limit` do `nack_sim.py`.

---

## 6. Ferramenta de bancada

`can_tool.py` ganhou os dois comandos, para configurar e conferir um módulo sem
passar pela nuvem:

```sh
python can_tool.py set-alarm --node 0x41 --channel 2 --min 11.8 --max 15.0
python can_tool.py set-alarm --node 0x41 --channel 2 --min 11.8 --max -
python can_tool.py get-alarm --node 0x41
```

Os valores são **volts de borne** (a ferramenta não conhece a fiação de
ninguém), e `-` é limite desligado — nunca `0`. O `sniff` decodifica os quatro
quadros do `0x4B`.

---

## 7. O que continua bloqueado, e o que não

- **Não bloqueia mais:** o item 1 da tabela do handoff original. O módulo grava,
  compara e avisa.
- **Bloqueia o teste de ponta a ponta:** o §1.1. Enquanto o CM06 não trocar os
  dois números, o alarme sobe com o lado invertido — que é pior do que não
  subir.
- **Fica em aberto, e é do quadro 11:** o opcode `0x4B` continua **provisório**,
  pela mesma ressalva do `0x4C`/`0x4D`/`0x4E` — o registro canônico do MTCP
  (`MTCP.ods`) segue fora do alcance desta máquina. Se ele disser outra coisa,
  ele manda, e muda nos três lugares (`~/CM2008`, `can_mtcp.h` do CM06 e a tela
  P4).
- **Uma pendência de hardware que toca este assunto:** o BSL invoke do MSPM0
  está no pino do **AI5**. Com ≥ ~25 V naquele borne a placa cai no bootloader em
  vez da aplicação. Não é deste cartão, mas é o canal analógico 5 — quem for
  ligar um banco de 24 V com divisor externo precisa saber. Está no
  `Firmware/V5/CLAUDE.md`, armadilha 1.
