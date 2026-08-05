# Resposta — a tela 10.1" já consome o horímetro 0x4D

**Data:** 02/08/2026 · **De:** firmware da tela (`matel-ivs-display-p4`, branch `feature/nav-n2k-travessia`)
**Para:** firmware do iVS2008 (`~/CM2008`) + gateway CM06 + plataforma
**Responde:** `HANDOFF-horimetro-bombas-tela-10.md`

> **Resumo em uma linha:** implementado e no ar — decode do `0x4D`, janela de
> 24 h por diferença de âncoras horárias, tratamento de reset e alarmes vindos
> do `bilge_alarm`. Duas correções ao handoff abaixo, e uma pergunta.

---

## 1. Feito

| Item do §3 do handoff | Situação |
|---|---|
| 1. Decodificar `0x4D` no `can_mtcp.c` | ✅ `MTCP_CMD_I2008CS`, mesmo nome do CM06 |
| 2. Trocar a contagem própria pela leitura do módulo | ✅ com reserva (ver §3) |
| 3. Guardar o par de referência na NVS | ✅ 25 âncoras horárias por bomba |
| 4. Tratar reset (`runtime_s` menor que a referência) | ✅ e mais dois casos |
| 5. Tirar o "contando desde…" | ✅ trocado pela ressalva que sobrou |

Também entrou a direção de **escrita**: `cm_reset_counter(nó, canal)` monta o
`0x4D` endereçado com os bytes de guarda. Ainda **não** há botão na tela para
isso — quando houver, vai atrás de confirmação, porque é irreversível.

### Como a janela de 24 h é feita

Guardamos, por bomba, o acumulado no **início de cada hora** (anel de 25
âncoras, na NVS). `24 h` = acumulado atual − âncora de 24 h atrás. É o
hodômetro que vocês descreveram, e o mesmo anel serve às 12 barras do gráfico:
cada barra é a diferença entre duas âncoras vizinhas.

Duas consequências que a tela mostra em vez de esconder:

- **Âncora tirada no meio da hora** (tela ligada às 10h37) mede errado as duas
  horas vizinhas. Ela é marcada `parcial`, e as barras que dependem dela saem
  como **traço**, não como zero — zero é uma afirmação.
- **Janela ainda incompleta** (menos de 24 h de âncoras) faz o rodapé dizer
  "Janela parcial: últimas N h" em vez de chamar de 24 h o que não é.

### Descontinuidade

O acumulado andar **para trás** joga todas as âncoras daquela bomba fora e
recomeça. Cobre os três casos de uma vez: horímetro zerado no módulo, módulo
trocado, e a tela mudando de fonte (§3). Sem isso a subtração daria negativo.

---

## 2. ⚠️ Duas correções ao handoff

### 2.1 `bilge_alarm` NÃO chegava na tela

O §3 diz: *"os limiares (`bilge_alarm`) já chegam pelo `/hmi/config`"*. Metade
verdade, e a metade que faltava era a nossa:

- **A plataforma emite mesmo** — `hmi_config.py:237-247`, dentro de
  `di_role == "bilge_pump"`, e o campo está no `response_model`
  (`schemas/hmi.py:79`).
- **A tela nunca leu.** O único parser do `/hmi/config` é o `parse_config()`
  do `hmi_cloud.c`, e ele não tinha `bilge_alarm` — a chave era descartada em
  silêncio, como cJSON faz com tudo que não se pede. O limiar continuava sendo
  a constante `ALERTA_CICLOS 12`.

**Agora lê**, e avalia os quatro critérios:

| Critério | Contra o quê |
|---|---|
| `continuous_run_min` | borda do `di_mask` (é estado instantâneo, não acumulado) |
| `window_cycles` | diferença de âncoras na janela |
| `window_runtime_min` | idem |
| `window_volume_l` | idem × vazão |

`cooldown_min`, `notify_company_users`, `extra_phones` e `extra_emails` são
ignorados de propósito: notificação é da plataforma, a tela só acende a faixa.

**Ressalva de resolução:** o horímetro tem granularidade de **1 hora**, então
`window_min` é arredondado para cima em horas — uma janela de 90 min é
avaliada em 2 h. Se isso for apertado demais para algum barco, é o `sel` do
byte 0 que resolve (ver §4).

### 2.2 O opcode: conferimos, e bate

Auditamos `0x4D` nas sete árvores (`~/CM2008`, gateway, as duas telas, test28,
mobile, CM01). Está livre em todas; as únicas ocorrências são o próprio
horímetro. Confirmamos também o quadro contra o emissor: `types.h:77`,
`processor.cpp:143-165`, `hal/can.cpp:100-103` — DLC 8, `destiny` 0xFF, ID
`0x1FFF{src}4D`, u32 LE + u24 LE saturado. **O layout do handoff está correto.**

O que **não** conseguimos conferir é o registro canônico (`MTCP.ods`,
`IVS2008_extensions.md`): continua inacessível daqui. Então o `0x4D` segue
provisório e agora custa **quatro** lugares para mudar, não três — o
`can_mtcp.h` da tela entrou na lista.

---

## 3. Onde discordamos do §3.2: a contagem própria FICA

O handoff pede para trocar a contagem por borda pela leitura do módulo. Fizemos
isso, mas **mantivemos a contagem própria como reserva**, e não por apego.

A tela nem sempre fala CAN com o módulo. Quando o nó não está neste barramento,
o tráfego vai pelo CM06 por BLE — e o CM06 **não repassa o `0x4D` por BLE**:
conferimos, o `ivs_wire.h` dele tem cinco características (State, Command,
Status, Labels, Assets) e o `iw_state_t` de 24 B não tem contador. O
`cm_node_counters()` de vocês tem um único consumidor, o `MT2,…,CNT` do
uplink serial.

Sem reserva, todo barco em que a tela fala pelo CM06 mostraria a página de
bombas vazia. Então:

- **fonte MÓDULO** quando o `0x4D` chega — é a verdade, conta com a tela
  desligada;
- **fonte LOCAL** quando não chega — as bordas do `di_mask` alimentam o mesmo
  acumulado, e daí para a frente o pipeline é idêntico;
- trocar de fonte é tratado como descontinuidade (âncoras fora), porque são
  dois odômetros diferentes;
- o rodapé do gráfico **diz qual fonte está valendo**.

**Se vocês acrescentarem uma característica de contadores no BLE do CM06, a
reserva vira código morto e sai.** É a nossa preferência — digam se faz sentido
aí.

Um detalhe de robustez que talvez valha para o CM06 também: o `seen` é
grudento, o que é certo (distingue "canal ainda não varrido" de "horímetro
zerado"), mas **sem envelhecer o dado**, um módulo que saia do barramento
deixa o acumulado congelado — e uma janela de 24 h feita por diferença vai
encolhendo até zero enquanto a bomba trabalha. Aqui o horímetro expira em
**30 s** sem quadro (varredura leva 3 s).

Ainda no CM06: `on_report_counter()` chama `mark_present()`. Como o `0x4D` sai
a cada 250 ms, um módulo que pare de emitir `0x41`/`0x42` mas siga varrendo
contadores **nunca** será marcado STALE aí. Na tela deixamos o `0x4D` **fora**
do `mark_present` de propósito: aqui `present` governa se o estado das entradas
está fresco, e um `di_mask` congelado exibido como vivo é exatamente a mentira
que o STALE existe para evitar.

---

## 4. Sobre o `sel` — sim, queremos

O §2c oferece usar o nibble `sel` para acrescentar um campo. Duas coisas, em
ordem de utilidade para a tela:

1. **`run_s` da operação em curso** (o que vocês ofereceram). Resolve a tela
   que bootou no meio de um ciclo: hoje o `continuous_run_min` só conta a
   partir da borda que a tela viu.
2. **Um `sel` com resolução mais fina** — por exemplo o acumulado dos últimos
   N minutos — só se a janela de 1 h se mostrar grossa demais na prática. Não
   peça ainda; é especulação nossa.

O item 1 é o que pedimos. Diga se cabe.

---

## 5. Estado da verificação

| O quê | Como |
|---|---|
| Decode do `0x4D` | ✅ varredura sintética das 12 DIs injetada em `on_frame`, `seen=0x0FFF`, canais 2 e 5 com 180 s/3 e 360 s/6 |
| Ponta a ponta até a tela | ✅ as três bombas trocaram para a fonte MÓDULO com os valores certos por canal |
| Contra o módulo real | ⬜ **não** — o iVS2008 da bancada ainda está com o firmware antigo (nenhum `0x4D` no fio) |
| Boot, sem panic | ✅ |

A ferramenta de bancada ficou no repo: `cm_teste_4d(0x41)`, atrás de
`-DTESTE_4D`. Quando gravarem o firmware novo no módulo da bancada, avisem que
rodamos contra o fio de verdade.

**Um susto que vale registrar:** as duas tabelas novas somam ~3 KB e, no
`.bss`, derrubaram a placa em boot loop — `Could not reserve internal/DMA pool
(0x101)`. A RAM interna desta placa está a menos de 3 KB do limite em que a
reserva de 64 KB contíguos do `esp_psram` falha. Ambas foram para a PSRAM. Se
o CM06 ou o CM2008 estiverem igualmente apertados, é o tipo de coisa que só
aparece no boot seguinte.
