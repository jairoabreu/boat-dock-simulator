# Arquitetura v2 — UIN como identidade universal

> **Status:** proposta para revisão · **Data:** 01/08/2026
> **Escopo:** protocolo dos equipamentos (iVS2008, CM06, DOT460, tela 10.1"),
> gateway Go e plataforma web.
>
> Convívio: **portas novas**, protocolo antigo intocado. Nada do que está em
> campo hoje é afetado até a migração explícita de cada barco.

---

## 1. O problema que isto resolve

Hoje a configuração de automação é chaveada por **(rastreador, `node_id`)**.
O `node_id` é o endereço CAN do iVS2008 — que é **derivado do serial**
(`0x41 + serial % 15`) e **renegociado a cada entrada no barramento**.

Consequência medida em campo (01/08/2026): um ciclo de energia mudou o módulo
de `0x42` para `0x41` e **invalidou os 48 canais de uma embarcação de uma vez**.
Sintomas correlatos no mesmo dia: canais órfãos, o mesmo canal físico
configurado em dois nós com rótulos diferentes, e módulo "excluído" que
reaparecia.

**Causa raiz única:** um endereço volátil está sendo usado como chave de
identidade.

## 2. Princípio

> **O UIN é a identidade. O endereço é circunstancial.**

Todo equipamento tem um **UIN** (Unique Identification Number) imutável,
gravado de fábrica. Toda mensagem que **sai do barco** carrega o UIN de quem a
originou. A plataforma resolve `UIN → equipamento → embarcação` no ingest.
Nenhuma topologia precisa ser cadastrada.

## 3. UIN por tipo de equipamento

| Equipamento | Origem do UIN | Formato | Exemplo |
|---|---|---|---|
| DOT460 (rastreador 4G) | IMEI do modem | 15 dígitos | `862092066689393` |
| CM06 (gateway CAN↔4G/WiFi) | MAC BLE | 12 hex | `3030F9281A7E` |
| iVS2008 (relés) | eFuse BLK3 | 10 dígitos | `2606200005` |
| Tela 10.1" | MAC BLE do C6 | 12 hex | `1020BAF3C8E6` |

No fio o UIN trafega **como texto, sem prefixo de tipo** — o tipo é deduzido do
cadastro. Manter o identificador natural evita uma tabela de tradução e um
ponto de divergência a mais.

## 4. ⚠️ A fronteira CAN — onde o UIN NÃO vai

Um frame CAN tem **8 bytes de dados no total**. O serial de 64 bits do iVS2008
ocupa os 8 bytes inteiros — medido no address-claim real:

```
address-claim src=0x41 dlc=8 [C5 74 57 9B 00 00 00 00] → serial 2606200005
```

Pôr o UIN em cada mensagem CAN exigiria **fragmentar toda leitura em 2 frames**,
dobrando o tráfego de um barramento que já reporta a cada 200 ms.

**Regra:**

- **Dentro do barco (CAN):** `node_id` continua sendo o endereço de enlace —
  é exatamente o papel dele, como um MAC numa rede local.
- **Na fronteira (CM06):** traduz `node_id → UIN` usando a tabela de
  address-claim que ele **já mantém**, e injeta o UIN na mensagem que sobe.
- **Fora do barco:** **sempre UIN**, nunca `node_id`.

A plataforma **nunca vê nem armazena `node_id`** como chave. Se ele aparecer,
é como atributo informativo de diagnóstico.

## 5. Gramática das mensagens

### 5.0 ⚠️ O protocolo do rastreador NÃO muda

O DOT460 é de terceiro — não temos acesso ao firmware dele. Portanto:

- O **envelope do rastreador é intocável** (frame `DOT;...` na subida,
  `DOT232;<counter>;<imei>;<payload>` na descida).
- O que muda é **exclusivamente o `<payload>` que o CM06 injeta/recebe** pelo
  canal serial de passagem que o rastreador já oferece.

Ou seja: o MT2 vive **dentro** da carga útil, nunca no envelope do rastreador.
O rastreador continua se identificando pelo IMEI, do jeito dele; o UIN do
equipamento de origem viaja no payload do CM06.

### 5.1 Subida (equipamento → plataforma)

Payload do CM06 — o mesmo nos dois transportes:

```
MT2,<uin_emissor>,<tipo>,<seq>,<payload>
```

| Campo | Descrição |
|---|---|
| `MT2` | marca de versão (distingue do `IVS,...` legado no parser) |
| `uin_emissor` | UIN de **quem originou** o dado (o iVS2008, não o CM06) |
| `tipo` | `IO`, `INV` (inventário), `EVT` |
| `seq` | contador por emissor — dedup e correlação |
| `payload` | específico do tipo |

**Via 4G:** vai embutido no frame do rastreador, exatamente como hoje o
`IVS,INFO` já viaja — **sem nenhuma mudança no rastreador**:

```
DOT;001;862092066689393;<...campos do rastreador...>;MT2,2606200005,IO,0041,DI=000,DO=01,AI=9437,...
└────────── frame do rastreador (INTOCADO) ──────────┘└────── payload do CM06 (MUDA) ──────┘
```

**Via WiFi:** o CM06 fala direto com a plataforma, mesmo payload, sem envelope:

```
MT2,2606200005,IO,0041,DI=000,DO=01,AI=9437,...
```

> É isto que torna o **meio irrelevante**: o UIN está no payload, então 4G,
> WiFi ou qualquer transporte futuro entregam a mesma informação identificável.
> O IMEI do rastreador continua servindo para saber por qual conexão a
> mensagem chegou — é dado de transporte, não de identidade.

### 5.2 Descida (plataforma → equipamento)

Endereçada **ao UIN do destinatário final**, nunca ao endereço de enlace.
Via 4G, usa o mesmo `DOT232` de passagem que o rastreador já implementa:

```
DOT232;<counter>;<imei_do_rastreador>;MT2,2606200005,CMD,SET,0,1
└──── envelope do rastreador (INTOCADO) ────┘└──── payload (MUDA) ────┘
```

Via WiFi, só o payload:

```
MT2,2606200005,CMD,SET,0,1
```

**Roteamento:** o gateway mantém um mapa vivo `UIN → conexão`, alimentado pelas
subidas. Ele descobre sozinho que o `2606200005` está atrás do rastreador
`862092066689393` (ou numa conexão WiFi) e escreve no socket certo. O CM06
traduz `UIN → nó corrente` e emite no CAN.

**Consequência:** um reendereçamento do módulo **não quebra nada** — nem a
configuração, nem o acionamento.

### 5.3 Confirmação

Resposta ecoa o `seq` e o UIN do executor:

```
MT2;2606200005;ACK;0210;OK
```

O `ACK` só é emitido **depois de aplicar** — diferente de hoje, em que o `RES`
do DOT460 confirma apenas o recebimento e não prova execução (medido: comando
confirmado com `RES` enquanto o `DO` permaneceu `00`).

## 6. Portas — convívio com o legado

Protocolo antigo **intocado**. O novo entra em portas próprias:

| Porta | Protocolo | Estado |
|---|---|---|
| `5000` | jsonline | legado, inalterado |
| `9000` → `15001` | DOT460 (frota Aquarium) | legado, inalterado |
| `15001` | DOT460 ASCII | legado, inalterado |
| `15002` | CM06 WiFi (captura raw) | legado, inalterado |
| **`15003`** | **MT2 via 4G** — DOT460 completo **+** payload MT2 (superconjunto) | **novo** |
| **`15004`** | **MT2 via WiFi** (CM06 direto) | **novo** |

### ⚠️ A porta nova é SUPERCONJUNTO da antiga, não alternativa

Primeira versão da `:15003` descartava toda linha que não fosse MT2 —
**inclusive posição e telemetria de motor do próprio rastreador**, que viajam
no mesmo envelope. Apontar um barco para lá o faria perder telemetria, e
"migrar é só reapontar a porta" não se sustentava.

Hoje a `:15003` roda o **servidor DOT460 inteiro** e o MT2 entra como gancho
sobre a carga útil que o CM06 injeta. Um único frame produz as duas coisas.

Cada barco migra quando o firmware dele for atualizado — aí sim, basta
reapontar a porta. Os dois mundos convivem indefinidamente; nenhum flag day.

> Ao reapontar, deixe a porta antiga como **servidor secundário**: se a nova
> falhar, o rastreador volta sozinho em vez de sumir. Foi assim que a bancada
> migrou.

## 7. Mudanças na plataforma

### 7.1 Configuração chaveada por UIN

Hoje `io_channels` é `(device_id do rastreador, node_id, kind, channel)`.
Passa a ser **`(device_id do MÓDULO, kind, channel)`** — o `device_id` do
próprio iVS2008, cujo `hw_id` é o UIN.

O `node_id` sai da chave. Sobrevive como coluna informativa (último endereço
observado), preenchida pelo inventário.

### 7.2 Vínculo e topologia

- `parent_device_id` deixa de ser **obrigatório no cadastro** — passa a ser
  **observado** (preenchido pelo gateway a partir de quem encapsulou a
  mensagem).
- `node_id` sai do formulário — é reportado, não digitado.
- Cadastrar um equipamento = **UIN + tipo + embarcação**. Nada mais.

> ✅ **Cumprido em 08/08/2026 (#167).** `node_id` saiu do `DeviceCreate`/
> `DeviceUpdate`, do formulário de cadastro de equipamento e do gerenciamento
> de módulo da Automação IoT; a rota de reendereçamento manual
> (`POST .../io/modules/{node}/readdress`) foi removida. Criar módulo exige
> UIN. A coluna sobrevive como **último endereço observado**, escrita só por
> quem observa o barramento — o `SyncNodeID` do INV e `POST /hmi/inventory`.
>
> Junto veio a régua que fechou a duplicação: **num casco onde algum módulo
> tem UIN, leitura de I/O sem identidade não é módulo**. O CM06 subia a mesma
> placa duas vezes — por MT2 com serial e pelo `IVS,INFO` legado de cada
> endereço do address-claim dele —, e as legadas viravam card fantasma. O
> corte é na ingestão (`ErrEnderecoSemIdentidade`, no gateway) e na
> apresentação (`so_com_identidade`, nas três rotas que listam nó a nó). O
> parque legado, onde ninguém tem UIN, segue inteiro pelo endereço.

### 7.3 Ingest

O gateway resolve `UIN → device → vessel` e carimba a mensagem. Um UIN
desconhecido vira **órfão** (tabela que já existe), aparecendo em
Ferramentas → Administrativo para o operador vincular.

## 8. Autenticação — decisão registrada

**Decidido: sem token.** O encapsulamento resolve a identificação, e a
confiança é a mesma do modelo atual (o gateway confia no identificador do
frame).

**Fica um caso fora do modelo:** a tela de 10.1" fala **direto** com a
plataforma por HTTPS — não é encapsulada por ninguém. Sem token, quem souber
o MAC (que o BLE anuncia em broadcast) baixa a configuração do barco.

Duas saídas, ambas coerentes com esta arquitetura:

- **(A) recomendada** — a tela recebe a config **via CM06** (que já fala com
  ela por BLE/CAN). Deixa de ser cliente HTTPS, o token some naturalmente e
  a regra fica uniforme: *só CM06 e rastreador falam com o servidor*.
- **(B)** — a tela continua puxando direto e o endpoint de config fica aberto
  por UIN.

**Pendente de decisão.** Até resolver, o token da tela (`mtd_`) permanece
como está — funcionando e sem impacto no resto.

## 9. Migração dos dados existentes

1. **Backfill de UIN nos módulos**: hoje há iVS2008 com UIN provisório
   (`IVS-<rastreador>-<nó>`, criado na migração 072). O inventário do
   equipamento substitui pelo serial real na primeira reportagem.
2. **Repontar `io_channels`** do rastreador para o módulo: para cada canal,
   `device_id ← device do módulo com aquele (parent, node_id)`. Reversível.
3. **Canais sem módulo correspondente** (órfãos de reendereçamento) vão para
   uma tabela de quarentena, não são apagados — o operador decide.
4. `node_id` vira informativo em `io_channels` (mantido para diagnóstico).

## 10. Ordem de implantação

| # | Etapa | Quem | Depende de |
|---|---|---|---|
| 1 | ✅ Fechar a gramática MT2 (este doc) | todos | revisão |
| 2 | ✅ Porta `15003`/`15004` no gateway com parser MT2 (só ingest) | plataforma | 1 |
| 3 | ✅ CM06: injetar UIN na subida (traduzir UIN→nó na descida fica com a etapa 5) | firmware | 1 |
| 4 | ✅ Migrar `io_channels` para chave por UIN | plataforma | 2 |
| 5 | ✅ Descida por UIN (mapa vivo no gateway) | plataforma | 3, 4 |
| 6 | iVS2008: address-claim já expõe o serial — **sem mudança necessária** | — | — |
| 7 | ✅ Migrar bancada para as portas novas e validar ponta a ponta | todos | 5 |
| 8 | Decidir (A) ou (B) para a tela | produto | — |

### ✅ Etapas 1 e 2 concluídas (01/08/2026)

Gramática fechada e implementada em `matel-gateway/internal/protocols/mt2/`:

```
MT2,<uin>,<tipo>,<seq>,<K=V,...>[|#|<crc>]

tipo   IO | INV | EVT | ACK
IO     NODE=41 (hex, informativo) · DI=000 · DO=01 · AI=9437|9448|... (mV)
```

**CRC identificado** por força bruta contra frames reais da bancada:
**CRC-16/CCITT-FALSE** (poly `0x1021`, init `0xFFFF`, sem reflexão, sem XOR
final), calculado sobre o texto **incluindo o `|#|` final`**. Vetores fixados
em `parse_test.go`:

| Span | CRC |
|---|---|
| `DOT232\|SVR\|IVS,SET,41,2,1\|#\|` | `7DC8` |
| `DOT232\|101\|1\|#\|` | `0C87` |

> Efeito colateral: o `dot_crc()` do CM06 usava init `0x0000` com complemento
> final — algoritmo diferente. **Toda subida ia com checksum errado**; como
> nada validava, passou despercebido. Corrigido no firmware.

**Validado no dev (01/08):** três frames de IO — WiFi com CRC, WiFi sem CRC e
4G dentro do envelope do rastreador — caíram no `device` do **módulo**,
resolvidos por UIN, com `io_telemetry` + `device_io_state` corretos. CRC
errado, UIN desconhecido (virou órfão) e linha não-MT2 foram rejeitados sem
derrubar a conexão. O DOT460 na `:15001` seguiu operando normalmente durante
todo o teste.

### ✅ Etapa 3 concluída (01/08/2026)

O CM06 aprende o UIN do **address-claim** do iVS2008 (payload de 8 bytes =
serial u64 LE) e guarda em **NVS**.

> O claim só é emitido quando o **módulo** entra no barramento. Provocar um
> novo exigiria **contestar o endereço** — e um contest pode fazer o módulo
> **trocar de endereço**, exatamente a instabilidade que esta arquitetura
> existe para eliminar. Então não se provoca: aprende-se uma vez e guarda-se.
> Basta um claim na vida do par (gateway, módulo), e o cache sobrevive a
> reboot do gateway.

Sem serial conhecido, o MT2 daquele nó **não é emitido** — não se inventa
identidade.

#### ⚠️ Regra de ouro do fio: `|` é proibido em payload MT2

O `|` é o delimitador do envelope do rastreador
(`DOT232|101|2|<payload>|#|<crc>`). Um payload que o contenha é **mutilado**
no transporte 4G.

Medido em 01/08/2026: os frames de `IO` com `AI=9437|9448` **nunca chegavam**,
enquanto `INV` e `IVS,INFO` passavam sempre. Uma sonda de comprimento no
firmware descartou a hipótese de tamanho — payloads de até **120 chars** sem
`|` passaram todos. Por isso:

- separador de `AI` é **`:`**
- sufixo de CRC é **`*<hex4>`**, não `|#|`

Também: o rastreador **fecha o campo com `;`**, e ele não pode entrar no
payload — quebrava o último valor de `AI` na conversão para inteiro.

**Validado ponta a ponta:** frames reais da bancada (`MT2,2606200005,IO,0007,
NODE=41,DI=000,DO=00,AI=9115:9115:...`) reenviados para `:15003` e ingeridos
no `device` do módulo, resolvidos por UIN.

### ✅ Etapa 4 concluída (01/08/2026)

`io_channels` e `device_io_state` passam a ser chaveados pelo **device do
módulo**. Unicidade nova: `uq_io_channels_device_kind_channel` — o `node_id`
saiu da chave e sobrevive como último endereço observado.

- **Migração 073**, reversível. Canais sem módulo correspondente vão para
  `io_channels_quarentena` — **não são apagados**.
- **`matel/services/io_scope.py`** é o resolvedor único. As URLs continuam
  aceitando o rastreador **ou** o módulo, então web e app não mudaram: quem
  endereça o rastreador enxerga os módulos dele.
- **Ingestão legada** no gateway resolve o módulo filho por `(imei, node_id)`
  e cai no rastreador quando não existe — parque não migrado continua
  gravando onde sempre gravou.

**Validado no dev:** 33 canais migrados, 0 em quarentena; `GET
/io/channels` e `/io/state` devolvem o mesmo endereçando rastreador ou
módulo; acionamento de saída confirmado (`do_mask=2` no snapshot, uma única
linha, no módulo).

### ✅ Etapa 5 concluída (01/08/2026)

O comando é endereçado ao **UIN do executor** e o gateway descobre sozinho por
onde ele está falando agora — o mapa `UIN → conexão` é alimentado pelas
**subidas**, não por cadastro.

```
MT2,<uin>,CMD,<seq>,OP=SET,CH=<n>,ST=<0|1>
```

O enquadramento sai conforme o transporte por onde o UIN foi visto:

| Transporte | Linha na descida |
|---|---|
| 4G | `DOT232;<counter>;<imei>;<payload>` — envelope do rastreador **intocado** |
| WiFi | `<payload>` cru |

O `<imei>` é **aprendido da subida**, não consultado no cadastro. É isso que
faz mover o módulo de barco, trocar o rastreador ou reendereçar o nó não
quebrarem o acionamento.

**Sem rota viva para o UIN, o comando cai no frame legado** — nada regride
enquanto o parque não migra.

#### `ACK` agora significa APLICADO

O `RES` do DOT460 confirmava só o recebimento pelo rastreador. Medido em
01/08/2026: um comando ficou `acked` por `RES` enquanto o `DO` do módulo
permanecia `00` — o rastreador nem repassava para a serial. No MT2 só o
**executor** confirma, e só **depois** de aplicar; UIN desconhecido, canal
inválido ou falha de CAN respondem `ERR=<motivo>` explícito.

A correlação usa o par **(UIN, seq)**, não só o seq: o seq é um contador por
emissor e dois módulos podem estar no mesmo número ao mesmo tempo.

#### Efeito colateral corrigido

O `request_frame` gravado passa a ser **o que o gateway realmente escreveu no
fio**. Antes o operador via em Comandos o frame legado montado pelo encoder,
mesmo quando a entrega tinha ido por MT2.

**Validado no dev, ponta a ponta:**

| Etapa | Evidência |
|---|---|
| Roteamento | `DOT232;275;862092066689393;MT2,2606200005,CMD,0113,OP=SET,CH=6,ST=1` entregue na rota viva do UIN |
| Correlação | counter `275` = seq `0113`; ACK levou o comando a `acked` |
| Execução no CM06 real | `CH=3 ST=1` → `DO` `02`→`0A` · `CH=3 ST=0` → `0A`→`02` · `CH=4 ST=1` → `02`→`12` |

### ✅ Etapa 7 — bancada migrada e validada (01/08/2026)

Rastreador `862092066689393` reapontado para `:15003` (primário), com `:15001`
como secundário de segurança. Em 3 minutos após a migração: **80 frames na
porta nova, zero na antiga**, 22 leituras de I/O ingeridas, e **quatro
acionamentos seguidos todos `acked` via MT2** (CH=2 liga/desliga, CH=1
liga/desliga).

#### Três defeitos que só a bancada migrada revelou

1. **Write deadline envenenado.** `WriteFrame` deixava um deadline vencido no
   socket. Deadlines em Go são absolutos: passados os 5 s, *qualquer* escrita
   posterior — de qualquer escritor — falha na hora com `i/o timeout`. Matava
   o segundo comando MT2 seguido.
2. **Rota morta no registro MT2.** Quem desvinculava a conexão era o listener
   MT2, que não roda mais no 4G. O mapa guardava socket morto.
3. **Corrida entre `Has()` e `WriteFrame`.** A conexão podia sair entre as
   duas chamadas — virava "device not connected" com o barco online.

**Falta:** o `hw_id` provisório `IVS-<rastreador>-<nó>` (criado na migração
072 para módulos que ainda não reportaram serial) **não é usado como UIN** —
tem o endereço dentro e voltaria a quebrar no reendereçamento. Esses módulos
seguem pela via legada até o inventário substituir pelo serial real.

## 11. O que isto NÃO resolve

Seja explícito para não criar expectativa:

- **Não conserta o acionamento quebrado de hoje** — ver o diagnóstico
  isolado em `DIAGNOSTICO-acionamento-ivs2008.md`. É firmware/fiação e está
  sendo tratado em paralelo.
- **Não adiciona autenticação** — decisão registrada na §8.
- **Não muda o firmware do iVS2008** — o address-claim já publica o serial.
