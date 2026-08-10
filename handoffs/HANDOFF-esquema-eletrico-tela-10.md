# Handoff — a plataforma passou a mandar o ESQUEMA ELÉTRICO

**Data:** 09/08/2026
**De:** plataforma web (`matel-web-platform-api` + `MaTel-web_platform`)
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)
**Responde a:** `matel-ivs-display-p4/docs/HANDOFF-baterias-tela-10.md` (06/08/2026)
**Cartão:** #190 (quadro 29 — Plataforma Web MarineTelematics)

> **Resumo em uma linha:** o `/hmi/config` ganhou a seção `banks`, o `bank_id`
> nos canais de bateria e o `switch_role` nas chaves comutadoras — os três
> campos que a página de Baterias consome e que até ontem nenhuma plataforma
> mandava. **Nada a fazer no firmware:** o parse do `hmi_cloud.c` já os lê.

---

## 1. O que mudou no `/hmi/config`

### 1.1 `banks` — seção nova, irmã de `areas` e `channels`

```json
"banks": [
  { "id": "3f1c…-a92b", "name": "Serviço", "chemistry": "lifepo4",
    "bank_role": "house", "nominal_voltage": null, "capacity_ah": null }
]
```

**Um banco por canal `ai_role: "battery"`.** É o modelo que o cadastro tem
hoje: o papel e a química moram no CANAL, porque é lá que o eletricista
cadastra a bateria. O `id` é o uuid do próprio canal — estável entre leituras,
que é tudo o que o firmware pede dele (lá ele morre virando índice).

O banco sai **mesmo sem papel e sem química cadastrados**. Isso é de
propósito: o banco EXPLÍCITO, com `bank_id` no canal, tira a tela do banco
*implícito* (aquele que o `hmi_cloud.c` inventa a partir de canal sem
`bank_id`), e o aviso da faixa do topo passa a apontar o que de fato falta —
"sem lugar no esquema" em vez de "canal sem bank_id".

### 1.2 `bank_id` no canal de bateria

Todo canal `ai_role: "battery"` agora sai com `bank_id` apontando para o banco
correspondente. O contador `n_sem_bank_id` da tela deve zerar.

### 1.3 `switch_role` na chave comutadora

```json
{ "kind": "do", "uin": 2608070000, "node_id": 66, "channel": 4,
  "label": "Paralelo de partida",
  "do_role": "battery_switch", "switch_role": "start_parallel" }
```

`do_role: "battery_switch"` é vocabulário novo do `do_role` (ao lado de
`windlass` e `hvac_power`). O `switch_role` só acompanha saída marcada assim —
a API recusa (422) o papel pendurado em outro `do_role`.

### 1.4 `switch_bank_a` / `switch_bank_b` — QUAIS bancos a chave comuta

> **Acréscimo de 09/08/2026 — cartão #194.** Este é o único trecho deste
> handoff que PEDE mudança de firmware; o resto continua sendo "nada a fazer".

```json
{ "kind": "do", "uin": 2608070000, "node_id": 66, "channel": 4,
  "label": "Paralelo de partida",
  "do_role": "battery_switch", "switch_role": "start_parallel",
  "switch_bank_a": "3f1c…-a92b", "switch_bank_b": "77e0…-1c40" }
```

Os dois valores são `banks[].id` **desta mesma config** — o mesmo id que o
`bank_id` do canal analógico usa, então resolvem pelo mesmo caminho que vocês
já têm (id → índice em `hc_config_t.banks`).

Só saem nos dois papéis que ligam **banco a banco**:

| `switch_role` | manda o par? | porque |
|---|---|---|
| `start_parallel` | **sim** | liga BB a BE |
| `emergency_crossover` | **sim** | liga um banco ao outro |
| `house_master` | não | liga o banco de serviço ao BARRAMENTO |
| `shore_charger` | não | liga o CAIS ao banco |

E só saem com o **par inteiro e resolvível**: se um dos dois não estiver
cadastrado, ou apontar para um canal que não está em `banks` (desabilitado, ou
deixou de ser bateria), a plataforma **omite os dois campos** — meio par não é
aresta, e um id fora de `banks` não vira índice nenhum aí. Nesse caso a
plataforma registra `WARNING`, mas para vocês é indistinguível de chave sem
polos, de propósito.

**Regime de conservação — o ponto importante:** chave **sem** o par mantém o
comportamento de hoje, isto é, a posição pela topologia fixa da
`esquema_resolve()`. Barco já configurado não muda em nada. O par é
obrigatório apenas na **criação** de uma chave nesses dois papéis (a API recusa
com 422 nomeando os bancos disponíveis) — nunca num `PATCH` de uma chave que já
existia sem ele.

**O que pedimos do lado de vocês** (cartão irmão no quadro 26): quando o par
vier, a chave é posicionada **entre esses dois bancos** e a aresta é desenhada
entre eles — pontilhada, **verde em movimento** com o relé acionado (`do_mask`),
**cinza estática** quando não. A maquinaria já existe (tile A8 tracejado, fluxo
por aresta, estado por relé); o que muda é a origem dos extremos da aresta:
config em vez de `fio_tab[]` fixa.

---

## 2. O vocabulário é o SEU, e a plataforma o impõe na porta

Copiado de `main/hmi_cloud.h` e de `esquema_resolve()` em
`main/screen_baterias.c`, e imposto como enum no cadastro
(`matel/services/esquema_eletrico.py`):

| Campo | Valores aceitos |
|---|---|
| `bank_role` | `house` · `start` · `genset` |
| `chemistry` | `agm` · `flooded` · `gel` · `lifepo4` |
| `switch_role` | `house_master` · `start_parallel` · `emergency_crossover` · `shore_charger` |

Papel fora dessa lista não entra no banco de dados, então não chega ao fio.
Era ele o gerador do aviso "sem lugar no esquema" — não há mais como produzi-lo
pela plataforma.

**A capacidade também veio de vocês, e é o detalhe que uma "unicidade" ingênua
erraria:** a `esquema_resolve()` tem **dois** nós de partida (BB e BE) e um de
serviço/gerador. Então a API conta VAGAS, não unicidade — `start` cabe duas
vezes por embarcação, `house` e `genset` uma. Estourar a vaga é **409** com a
frase dizendo QUAIS canais já ocupam. A UI avisa antes, enquanto o operador
escolhe o papel.

Cada `switch_role` tem uma vaga só, pelo mesmo motivo: um nó cada no desenho.

---

## 3. `chemistry`: o consumidor JÁ EXISTE — e é de segurança

O cartão supunha que o tipo da bateria talvez ainda não tivesse consumidor.
Tem: o `chem` do `hc_bank_t` é o que autoriza (ou nega) a estimativa de carga
pela tensão de repouso. Chumbo-ácido estima com "≈"; lítio mostra "—" porque a
curva é plana entre 20% e 90%; **sem química, também "—"**.

Consequência do modelo de hoje, e é intencional: o campo `chemistry` sai
**nulo** quando o operador não cadastrou o tipo. Semear um padrão ("agm") aqui
daria à tela licença para estimar um banco que pode ser de lítio. Nulo é a
verdade, e a tela já sabe o que fazer com ela.

A UI diz isso ao operador, com a frase mudando conforme a química escolhida —
não é enfeite de cadastro, é a razão de o campo existir.

---

## 4. O que a plataforma AINDA não manda, e por quê

| Campo | Situação |
|---|---|
| `nominal_voltage` | sai `null` — não há cadastro. A tela usa 12 V como escala da curva. |
| `capacity_ah` | sai `null` — não há cadastro. "Disponível" e "Capacidade total" ficam em "—", que é o correto: derivar Ah de um número inventado seria autonomia em horas, inventada. |
| `battery_current` · `battery_soc` · `battery_temp` | os `ai_role` não existem no cadastro da plataforma (só `battery`, que vocês já mapeiam para `HC_AI_BATT_V`). Sem eles a pílula diz "SEM MONITOR", que é a verdade: não há shunt na bancada. |

Os dois primeiros são cadastro de UI a fazer; os três últimos dependem do
monitor com shunt que o §2 do handoff de vocês pede como hardware. Nenhum é
bloqueante para o diagrama montar.

---

## 5. Tetos: quem descarta em silêncio, e quem avisa

`HC_MAX_BANKS` = 6 e `MAX_CHAVES` = 6. Acima disso o firmware descarta em
silêncio — o silêncio é dele, o aviso passou a ser nosso: o `hmi_config.py`
registra `WARNING` com a embarcação e a contagem quando o barco passa do teto.
Não recusamos o cadastro: um sétimo banco continua sendo um banco, e a tela
diz na faixa do topo o que não coube.

---

## 6. `config_version`

Nada de especial a fazer: a versão é derivada do **hash do corpo**, então os
campos novos a fazem subir sozinha na primeira leitura de cada barco. A tela
rebaixa a config no ciclo normal.

---

## 7. Onde está, do nosso lado

* Migração `086_esquema_eletrico` — `bank_role`, `battery_kind`, `switch_role`
  em `io_channels`. E `088_polos_da_chave` — `switch_bank_a`/`switch_bank_b`
  (FK para o próprio `io_channels`, `ON DELETE SET NULL`: apagar um banco não
  apaga a chave, que é um relé parafusado no painel — ela volta ao regime de
  conservação).
* `matel/services/esquema_eletrico.py` — vocabulário e capacidade (o espelho
  do `hmi_cloud.h`; é o arquivo a mexer se o desenho ganhar nós).
* `matel/services/hmi_config.py` — a emissão.
* `matel/routers/iot.py` — o enum, a regra "papel mora com o papel" e o 409 de
  vaga ocupada.
* UI: o mesmo modal de canal da Automação IoT
  (`apps/nautica/src/components/iot/IoChannelsConfig.tsx`), com o aviso de
  papel repetido em tempo real (`src/lib/api/io-esquema.ts`).

**Não pedimos nada a vocês nesta rodada.** Se o diagrama montar na bancada com
o banco no lugar e as chaves desenhadas, o contrato fechou dos dois lados.

> **09/08/2026 (#194):** agora pedimos uma coisa só — o §1.4. O resto deste
> handoff segue valendo sem alteração.

---

## 8. A GRADE: a plataforma passou a dizer ONDE cada peça fica

> **Acréscimo de 09/08/2026 — cartão #202.** Este trecho PEDE firmware. O resto
> do handoff segue valendo sem alteração.

### 8.1 O problema, na queixa de quem usa

"A página de baterias nunca fica boa." Não é o desenho: é a ARRUMAÇÃO. Quem
posiciona as caixas hoje é a tela — pela topologia fixa da `esquema_resolve()`,
ou pelas correntes que a `esquema_por_config()` monta a partir dos polos do
§1.4. As duas são bons palpites, e nenhuma tem como saber que o banco de
partida daquele barco fica a bombordo, ou que o gerador daquele cliente mora
embaixo do serviço. Só quem olhou o painel sabe.

Então a plataforma ganhou um CONSTRUTOR: o operador arruma o esquema na web,
numa grade com a proporção do card de vocês, e a arrumação desce na config.
**Nenhuma imagem sobe** — sobe a CÉLULA de cada peça, e quem desenha continua
sendo a tela, com as caixas, os fios e as cores que ela já tem.

### 8.2 A grade é a de vocês, copiada

Nada de novo a acordar: são `CEL_MAX`×`LIN_MAX` da `esquema_por_config()`,
dentro do card de `PALCO_W`×`PALCO_H`.

| | valor | de onde |
|---|---|---|
| colunas | 7 | `CEL_MAX` (`screen_baterias.c`) |
| fileiras | 3 | `LIN_MAX` |
| card | 893 × 221 px | `PALCO_W` / `PALCO_H` |

O construtor da web desenha nessa grade e recusa na porta o que sair dela — uma
coluna 7 devolve 422 antes de chegar ao banco de dados.

### 8.3 O que muda no `/hmi/config`

**Seção nova `schematic`, irmã de `banks`:**

```json
"schematic": { "cols": 7, "rows": 3 }
```

**`pos` em cada peça** — nos itens de `banks[]` e nos canais com
`do_role: "battery_switch"`:

```json
"banks": [
  { "id": "3f1c…-a92b", "name": "Partida BB", "bank_role": "start",
    "pos": { "col": 0, "lin": 0 } }
],
"channels": [
  { "kind": "do", "channel": 4, "do_role": "battery_switch",
    "switch_role": "start_parallel",
    "switch_bank_a": "3f1c…-a92b", "switch_bank_b": "77e0…-1c40",
    "pos": { "col": 1, "lin": 0 } }
]
```

`col` é 0..`cols`−1 e `lin` é 0..`rows`−1 — as mesmas células que a
`esquema_por_config()` já preenche em `pt_col[]`/`pt_lin[]`.

### 8.4 TUDO ou NADA — e é o ponto do contrato

`schematic` **presente** = a grade deste barco está inteira, e toda peça tem
`pos`. **Ausente (`null`)** = regime de conservação: nenhum `pos` desce e vocês
arrumam o palco como sempre arrumaram, sem uma linha de diferença.

Não existe meio termo, e é de propósito. Grade pela metade obrigaria vocês a
misturar as posições que vieram com um arranjo automático para o resto — e duas
peças escolhidas por critérios diferentes acabam na MESMA célula, ou o fio de
uma cruza a caixa da outra. Basta uma peça na bandeja do construtor e a
plataforma segura a grade inteira (com `WARNING` do nosso lado nomeando a que
falta). **Barco já certificado não muda em nada:** sem ninguém abrir o
construtor, `schematic` sai nulo para sempre.

### 8.5 O que pedimos do lado de vocês (cartão irmão no quadro 26)

1. Ler `schematic` e o `pos` de cada peça. Com `schematic` presente, a
   `esquema_resolve()` **pula** as duas heurísticas e preenche
   `pt_col`/`pt_lin` direto da config: a maquinaria de coordenadas do passo 3
   da `esquema_por_config()` (passo horizontal pela fileira mais cheia, bloco
   centrado no palco) continua valendo tal e qual — o que muda é a ORIGEM das
   células.
2. Os FIOS continuam saindo dos polos do §1.4, não da grade. A grade diz onde
   as caixas ficam; quem liga quem já é o `switch_bank_a`/`switch_bank_b`. Uma
   chave posicionada entre dois bancos que ela não comuta é escolha do
   operador, e o fio deve seguir os polos, não a vizinhança.
3. `cols`/`rows` vêm para vocês CONFERIREM, não obedecerem: se um dia a grade
   de vocês crescer, uma config antiga com 7×3 deve pousar no canto em vez de
   esticar. E se vier maior que a de vocês (não vem hoje), a peça fora do
   alcance é o caso da faixa do topo — descartar em silêncio é o que esta
   demanda veio evitar.
4. Com `schematic` ausente, **nada muda**. Se o firmware de hoje for a campo
   sem tocar nada disso, ele continua funcionando exatamente como funciona.

### 8.6 `config_version`

Como sempre: a versão é o hash do corpo, então os campos novos a fazem subir
sozinha na primeira leitura de cada barco.

### 8.7 O fio com a grade: a invariante que o operador pode quebrar

> **Acréscimo de 09/08/2026 — cartão #205.** Nada a mudar no firmware; é um
> aviso sobre o que passa a chegar aí.

Hoje quem monta o palco monta o FIO junto, e o `fios_da_chave()` garante que o
`a` de cada trecho é a caixa da esquerda — a corrente nasce em fileira reta e
crescendo para a direita. Com a grade do §8.3 a coordenada passa a ser do
OPERADOR, e essa garantia deixa de valer sozinha: nada impede que ele ponha o
banco à direita da chave que o comuta, ou os dois em colunas e fileiras
diferentes.

Do lado do `monta_fio()` isso já tem desfecho definido, e é por isso que não
pedimos mudança: largura ou altura não positiva e o trecho simplesmente não
é desenhado; fileiras diferentes e o retângulo nasce na coluna do `a`, sem
tocar a caixa do `b`. **O que fizemos foi tirar essa surpresa da bancada:** o
construtor da web desenha os vínculos o tempo todo, com traço FIRME só onde a
regra acima produz fio, e pontilhado em âmbar (com a frase dizendo o motivo)
onde ela não produz. O operador conserta a arrumação olhando o quadro, antes de
a config descer.

Se um dia o desenho de vocês ganhar cotovelo — fio em L entre caixas de colunas
e fileiras diferentes —, é este parágrafo que muda dos dois lados: avisem, e o
construtor passa a chamar de firme o que hoje ele chama de torto.

### 8.8 Onde está, do nosso lado

* Migração `089_grade_do_esquema` — `esquema_col`/`esquema_lin` em
  `io_channels`, com CHECK de faixa e de par.
* `matel/services/esquema_eletrico.py` — `GRADE_COLUNAS`/`GRADE_FILEIRAS`,
  `grade_resolvida()` (o tudo-ou-nada) e `posicao_do_canal()`.
* `matel/services/hmi_config.py` — a emissão de `schematic` e dos `pos`.
* `matel/routers/iot.py` — 422 de célula fora da grade / em canal que não é
  peça, e 409 de célula já ocupada, nomeando o borne que a ocupa.
* UI: `apps/nautica/src/components/iot/EsquemaEletricoBuilder.tsx` (visão
  "Esquema elétrico" da Automação IoT) e a regra pura em
  `src/lib/api/io-grade.ts` — incluindo `vinculosDaGrade()`, o espelho do
  `fios_da_chave()` + `monta_fio()` que decide traço firme ou pontilhado (§8.7).

Verificado na dev em 09/08/2026: sem grade, `schematic: null` e todo `pos`
nulo; com a grade cheia, `schematic: {cols:7, rows:3}` e cada peça na sua
célula; tirando UMA peça, tudo volta a nulo.

---

## 9. A TELA CHEIA em QUADRANTES, e as LIGAÇÕES definidas na plataforma

> **Acréscimo de 09/08/2026 — cartão #207.** Este trecho PEDE firmware, e é o
> §8 na sua forma seguinte. **O §8 continua valendo palavra por palavra
> enquanto a tela de hoje estiver em campo** — ver §9.7, que é a razão de o
> `pos` que desce agora continuar sendo célula válida para ela.

### 9.1 O que muda no palco

A página de Baterias vai ser REFEITA. O esquema elétrico deixa de ser um card
de 893×221 px no meio da página e passa a ocupar a **tela inteira**
(1280×800 de paisagem útil), dividida em **quadrantes**: cada quadrante desenha
UM componente do esquema — um banco de baterias, uma chave comutadora.

Com o palco maior, uma coisa que se aguentava no card deixa de se aguentar: o
FIO ser dedução da tela. Até aqui vocês liam os polos do §1.4 e montavam a
corrente, ou caíam na topologia fixa da `esquema_resolve()`. Num card de 221 px
de altura o palpite errado custava pouco; numa tela inteira ele é a página. E
quem sabe se aquele barramento passa por ali é quem olhou o painel — o mesmo
que arrumou os quadrantes.

Então a LIGAÇÃO passa a ser definida na plataforma, no construtor da web, e
desce pronta.

### 9.2 A malha de quadrantes — e a divisão é PROPOSTA, não número copiado

Aqui há uma diferença importante em relação ao §8. Lá `cols`/`rows` eram
`CEL_MAX`/`LIN_MAX`, **de vocês**, copiados. A divisão dos quadrantes não é: é
escolha da plataforma, e a que está no ar hoje é

| | valor |
|---|---|
| colunas | 7 |
| fileiras | 5 |
| caixa de bateria | 174 × 127 px |
| caixa de chave | 96 × 82 px (fixa) |

> **Atualizado em 09/08/2026 — cartão #217 (plataforma).** Era 4×3 (#209).
> Virou **7×5**, que é exatamente o desenho do §10.3, e a virada está no ar
> **na DEV** (`api-dev`). O §10.4 continua valendo para a PRODUÇÃO — leiam-no
> com a redação nova.

**7×5, e a escolha está feita** — pelo Jairo, em 09/08/2026 (#217). O caminho
até aqui:

* 4×2 (#207) tinha 8 quadrantes, e o firmware aceita 6 bancos e 6 chaves — 12
  peças. Barco com mais de 8 não fecharia o palco, e pelo tudo-ou-nada do §8.4
  isso significaria **nada descer**;
* 4×3 (#209) deu 12 quadrantes, exatamente o teto do firmware — mas era antes
  de a malha saber estreitar a coluna da comutadora (§10.1);
* 7×5 (#217) é a página do §10.3: **4 colunas e 3 fileiras de bateria, com os
  corredores de chave entre elas, e as bordas do quadro em bateria.**

**O que mudou no teto.** Até o #217 quem limitava a divisão era o ENVELOPE do
§8 (`CEL_MAX`×`LIN_MAX`, 7×3): cada quadrante tinha de ser célula que a tela de
campo sabe ler. 7×5 não cabe lá — e o §10.4 explica por que isso deixou de
travar a escolha. O teto que sobra é o de vocês: `QD_COLS_MAX`×`QD_LINS_MAX`,
e a malha de hoje **bate nele**.

Note que a escolha não some do código: `MALHA_COLUNAS`/`MALHA_FILEIRAS` em
`esquema_eletrico.py`, com gêmeos em `io-grade.ts`, continuam sendo os dois
números que a definem. Trocá-la de novo é trocá-los (e alargar o CHECK da
migração, se a faixa crescer), e o construtor continua dizendo na cara quantas
peças passariam do que a malha comporta.

**O que o teste guarda agora.** O
`test_a_malha_cabe_no_envelope_do_paragrafo_8` era quem reprovaria a 7×5, e o
§10.4 pedia que ele não fosse afrouxado sem decisão escrita. A decisão está
escrita, e o teste não foi afrouxado: foi **partido em dois**, um guardando
cada metade da regra que ele antes misturava.

* `test_a_malha_cabe_no_teto_da_tela` — a malha ≤ `QD_COLS_MAX`×`QD_LINS_MAX`.
  É o teto que ainda é do desenho, e reprova a próxima divisão grande demais;
* `test_o_envelope_do_paragrafo_8_guarda_a_producao_nao_a_malha` — afirma que a
  malha **não** cabe no §8, e diz por que isso é seguro: o envelope mede o
  ambiente de PRODUÇÃO, não a escolha. Gêmeos em `io-grade.test.ts`.

Um efeito da divisão vale dito: o arranjo automático do construtor põe banco,
chave, banco … na fileira, então uma corrente de até **4 bancos** cabe numa
fileira só (na 4×3 cabiam 2, e a de 3 transbordava). E a semente agora respeita
a alternância também na vertical — correntes nas fileiras **pares**, corredor
nas ímpares.

O que a escolha tem de respeitar, dos dois lados, está no §9.7 e no §10.5.

### 9.3 O que muda no `/hmi/config`

**`schematic` ganha `version` e `links`:**

```json
"schematic": {
  "version": 2,
  "cols": 7,
  "rows": 5,
  "links": [
    { "a": "3f1c…-a92b", "b": "9d20…-77c1", "from_poles": true },
    { "a": "3f1c…-a92b", "b": "77e0…-1c40", "from_poles": false }
  ]
}
```

* `version` — 1 é o §8 (a grade dentro do card, sem ligações), 2 é isto.
  **Desce sempre.** O firmware de hoje não olha o campo e não precisa: ver
  §9.7.
* `cols`/`rows` — agora são a malha de quadrantes. Mesma semântica de antes:
  vêm para CONFERIR, não para obedecer.
* `links` — os fios, e é a novidade. Lista, nunca nula quando `schematic`
  existe; vazia significa "nenhum fio", não "não sei".

**`switch_id` nos canais com `do_role: "battery_switch"`:**

```json
{ "kind": "do", "channel": 4, "do_role": "battery_switch",
  "switch_role": "start_parallel",
  "switch_id": "9d20…-77c1",
  "switch_bank_a": "3f1c…-a92b", "switch_bank_b": "77e0…-1c40",
  "pos": { "col": 1, "lin": 0 } }
```

A chave precisava de um NOME para ser apontada por um fio. O banco já tinha
(`banks[].id`); a chave passa a ter o mesmo, com a mesma promessa: estável
entre leituras, e do outro lado ele morre virando índice.

### 9.4 As LIGAÇÕES: duas naturezas, uma lista

`a` e `b` são ids de peça — um `banks[].id` ou um `switch_id`. **A ligação não
tem direção:** `a`/`b` vêm em ordem canônica só para a lista não dançar entre
leituras (o `config_version` é o hash do corpo). Não leiam a ordem como sentido
de corrente.

`from_poles` separa as duas naturezas:

* **`true`** — o fio nasceu dos POLOS da comutadora (`switch_bank_a`/`_b`).
  Isso é **verdade elétrica**: é o que a chave de fato comuta, e é o fio que
  pode acender junto com o acionamento se vocês quiserem. Cada par de polos
  resolvido vira dois links: `banco_a`—chave e chave—`banco_b`, que é
  exatamente o que o `fios_da_chave()` montava.
* **`false`** — foi DESENHADO no construtor, e é **topologia do desenho**: o
  barramento que só existe naquele painel, o retorno que o eletricista quer
  ver, o banco ligado ao banco. Não tem consequência elétrica nenhuma — some do
  circuito e continua sendo um traço.

**Os polos NÃO saíram.** Eles continuam em cada canal de chave, como no §1.4, e
continuam sendo a autoridade sobre o que a chave comuta. O que o `links` faz é
dizer o DESENHO por extenso, incluindo o que os polos já diziam — desenhar no
construtor um fio que os polos já descrevem não cria link novo, funde-se ao que
já está lá.

### 9.5 TUDO ou NADA, também para o fio

O `links` só desce **dentro de um `schematic` presente**, e `schematic` só está
presente quando a malha fecha inteira (§8.4, sem alteração). Não é rigor por
rigor: um fio entre duas caixas que a tela arrumou sozinha ligaria o que ela
escolheu, não o que o operador desenhou — pior que fio nenhum.

Sem `schematic`, portanto, nada muda para vocês: nem posição, nem fio, e a
`esquema_resolve()` monta o palco como sempre montou.

### 9.6 O que pedimos do lado de vocês (cartão irmão no quadro 26)

1. **Desenhar o palco em quadrantes**, lendo `cols`/`rows` e o `pos` de cada
   peça — a mesma leitura do §8.5 item 1, num palco de tela cheia.
2. **Desenhar o BANCO como bateria automotiva**: bloco com os dois terminais
   em cima, não uma caixa com texto. O construtor da web já desenha assim, e a
   promessa dele é "ficou bom aqui = ficou bom lá" — se o quadro mostra bateria
   e o vidro mostra retângulo, a promessa some.
3. **Desenhar os `links` em vez de deduzir o fio.** Com `schematic.version >=
   2`, a `esquema_resolve()` pula a montagem de correntes: os fios são os que
   vieram. E aqui entra o pedido do §8.7 que ficou registrado para o dia em que
   viesse: **o fio precisa de cotovelo**. Entre quadrantes de colunas e
   fileiras diferentes, o `monta_fio()` de hoje pendura o retângulo no ar; num
   palco de 8 quadrantes isso é o caso comum, não a exceção. Enquanto não
   houver cotovelo, o construtor marca esses fios como "só na tela nova" e o
   operador é avisado — mas o desenho fica devendo.
4. **`from_poles` é opcional de consumir.** Se vocês desenharem os dois iguais,
   está certo. Ele existe para o dia em que o fio da comutadora acompanhar o
   acionamento — aí o fio desenhado não deve acender junto, porque não é ele
   que a chave fecha.
5. **`version` é para CONFERIR.** Config com `version: 1` (não existe hoje, mas
   pode existir se rebaixarmos) não tem `links`: caiam na dedução de antes.
   Config com `version` maior que o que vocês conhecem: leiam `cols`/`rows`,
   `pos` e `links`, e ignorem o resto — nunca descartem o palco inteiro por não
   reconhecer o número.

### 9.7 A compatibilidade com o §8, e o que ela custa

Enquanto a tela de hoje estiver em campo, ela vai continuar recebendo este
`schematic`. Ela não conhece `version`, `links` nem `switch_id`, e vai ignorar
os três — o parser descarta o que não conhece. O que ela vai ler é `cols`,
`rows` e os `pos`, exatamente como no §8.

**Isso funcionou por uma escolha deliberada, enquanto a malha coube dentro da
grade 7×3 do §8** — foi assim na 4×2 e na 4×3: todo `pos` que descia (coluna
0..3, fileira 0..2) era célula válida para a `esquema_por_config()`, que
continua centrando o bloco no palco como sempre, e a tela de hoje desenhava o
barco arrumado em quadrantes como se fosse a grade dela, com menos colunas
ocupadas.

> **Não vale mais para a malha de hoje (#217).** A 7×5 tem `lin` 3 e 4, que o §8
> não conhece: a compatibilidade descrita neste parágrafo acabou — de propósito,
> e **só na DEV**. O §10.4 diz o que ela exige antes de ir à produção.

**A regra, escrita para quem for mexer:** uma divisão de quadrantes só vai para
o AMBIENTE em que há tela do §8 em campo se couber em `CEL_MAX`×`LIN_MAX`. Hoje
a tela de campo fala com a PRODUÇÃO (`api.marinetcs.com`) e a malha 7×5 vive na
`api-dev`, que nenhuma tela de campo alcança. Do nosso lado a regra está
guardada por dois testes, não por comentário — ver o fim do §9.2.

O que a tela de hoje NÃO recebe é o fio desenhado — ela não lê `links`. O
construtor diz isso ao operador no traço de cada fio: firme = as duas telas
desenham; tracejado = só a de quadrantes; pontilhado âmbar = não chega a vidro
nenhum.

### 9.8 `config_version`

Como sempre: a versão é o hash do corpo, então os campos novos a fazem subir
sozinha na primeira leitura de cada barco.

### 9.9 Onde está, do nosso lado

* Migração `090_ligacoes_do_esquema` — tabela `io_schematic_links`, com o par
  em ordem canônica (CHECK `a < b`) e UNIQUE no par.
* Migração `091_malha_7x5` (#217) — alarga o CHECK `ck_io_channels_esquema_`
  `grade` de `lin` 0..2 para 0..4. A faixa só cresce, então nada gravado muda;
  a volta zera a célula das peças que só existem na malha nova (bandeja).
* `matel/services/esquema_eletrico.py` — `MALHA_COLUNAS`/`MALHA_FILEIRAS` e
  `TELA_W`/`TELA_H` (a malha), `ENVELOPE_COLUNAS`/`ENVELOPE_FILEIRAS` (a grade
  do §8, agora envelope), `celula_na_malha()`, `par_da_ligacao()`,
  `recusa_da_ligacao()`, `ligacoes_dos_polos()` e `ligacoes_no_fio()`.
* `matel/services/hmi_config.py` — a emissão de `schematic.version`,
  `schematic.links` e do `switch_id`.
* `matel/routers/iot.py` — `GET`/`POST`/`DELETE`
  `/devices/{id}/io/schematic/links`, com 422 de ponta que não é peça e 409 de
  fio duplicado (nomeando os polos quando é o caso).
* UI: `apps/nautica/src/components/iot/EsquemaEletricoBuilder.tsx` (o palco em
  quadrantes, o modo "Ligar peças", o desenho de bateria automotiva) e a regra
  pura em `src/lib/api/io-grade.ts`.

## 10. A malha deixou de ser HOMOGÊNEA: trilhos largos e finos

> **Acréscimo de 09/08/2026 — cartão #212 (tela).** Isto **já está no firmware**
> e **não pede nada de vocês para funcionar**: a malha 4×3 de então continuava
> descendo igual, e nenhuma peça mudava de célula. O §10.3 era o único ponto que
> PEDIA — e a plataforma o atendeu no mesmo dia (#217): a malha da dev é 7×5.

### 10.1 O que mudou na tela

Dividir a página em quadrantes IGUAIS dava à comutadora — nome curto, uma
lâmina e uma palavra — o mesmo espaço da bateria, que tem desenho, tensão,
carga e veredito. Sobrava de um lado e faltava do outro.

Agora **cada coluna e cada fileira tem tamanho próprio**, e o critério é o que
ela carrega, não o índice:

* **trilho LARGO** — tem pelo menos um BANCO. Caixa de até 284×284 px.
* **trilho FINO** — só chaves, ou vazio (aí é corredor de fio). Caixa **fixa**
  de 96×82 px: a chave não engorda por sobrar espaço, e a bateria é que
  aproveita a sobra.

Quando não há peça bastante para encher a página, o quadro **centraliza** em vez
de esticar caixa que já está grande o bastante.

### 10.2 O que isso faz com a malha 4×3 de hoje

Nada de contrato, e uma melhora de desenho. No barco da bancada (3 bancos, 1
comutadora, `schematic` v2 4×3) a coluna 1 é só da chave e estreitou; as colunas
0 e 2 são de banco e engordaram:

```
QUADRO em quadrantes (v2, malha 4x3 · 2 coluna(s) e 2 fileira(s) de banco,
caixa 284x253 · chave 96x82)
```

A caixa da bateria passou de 273×192 para **284×253 px** — e com isso subiu de
porte: o rodapé (corrente, temperatura, disponível) e a nota da origem do número
voltaram para dentro do quadrante.

### 10.3 O pedido: a malha PODE crescer para 7×5

> **SUPERADO pelo §11 (cartão #218, 09/08/2026).** O Jairo viu a 7×5 montada na
> bancada e recusou o próprio pedido: o desenho abaixo, lido célula a célula,
> vira um mar de 35 caixas quase iguais. **A malha em PIXEL continua valendo — é
> a régua do §11.2 —, mas o ENDEREÇO que desce mudou:** 4×3 células de banco, e
> a chave numa ARESTA entre duas delas. Leia o §11 antes de implementar daqui.

O firmware aceita agora até **7 colunas × 5 fileiras**, e é essa a malha que dá
o quadro que o Jairo desenhou no #212:

```
[bateria] (chave) [bateria] (chave) [bateria] (chave) [bateria]
( chave )    ·    ( chave )    ·    ( chave )    ·    ( chave )
[bateria] (chave) [bateria] (chave) [bateria] (chave) [bateria]
( chave )    ·    ( chave )    ·    ( chave )    ·    ( chave )
[bateria] (chave) [bateria] (chave) [bateria] (chave) [bateria]
```

**4 colunas e 3 fileiras de bateria, 3 colunas e 2 fileiras de comutadora entre
elas, e as BORDAS do quadro são baterias** — bancos nas células PARES, chaves
nas ÍMPARES. Medido na tela: bateria **174×127 px**, chave **96×82 px**.

> **Feito — cartão #217, 09/08/2026.** `MALHA_COLUNAS`/`MALHA_FILEIRAS` são
> **7×5** na DEV, com os gêmeos de `io-grade.ts` e o CHECK da migração `091`
> alargado para `lin` 0..4. O arranjo automático passou a semear exatamente
> este desenho: bancos nas células PARES dos dois eixos, chaves nas ÍMPARES.
> Ver §9.2. Para a produção, §10.4.

Trocando `MALHA_COLUNAS`/`MALHA_FILEIRAS` para 7×5 (e os gêmeos em
`io-grade.ts`), a tela desenha isso sem mais nenhuma mudança dos dois lados. O
arranjo automático do construtor só precisa passar a pular uma célula entre duas
peças — o que ele já faz em espírito ao pôr "banco · chave · banco".

**Nada obriga a 7×5.** Qualquer malha até 7×5 funciona, e a regra dos trilhos é
a mesma em todas.

### 10.4 O custo, e é ele que decide o prazo — do AMBIENTE, não da malha

> **Redação nova — cartão #217, 09/08/2026 (Jairo).** O §10.4 continua de pé; o
> que mudou é o que ele proíbe. A proibição é do **ambiente de PRODUÇÃO**, não
> da escolha da malha: na DEV a virada já aconteceu.

**7×5 NÃO cabe no envelope do §9.7.** A grade do §8 é 7×3: uma peça em
`lin: 3` ou `lin: 4` some da tela que só conhece o §8, e o §8.4 é tudo-ou-nada
— some o esquema INTEIRO daquele barco, não a peça. Isso não mudou, e é por
isso que o parágrafo existe.

**O que destrava a virada é a topologia dos ambientes.** As telas em campo
falam com a **produção** (`api.marinetcs.com`). O construtor, a migração e todo
este trabalho vivem na **dev** (`api-dev`), que nenhuma tela de campo alcança —
a regra da casa é deploy só na dev. Uma malha 7×5 na dev não apaga o esquema de
barco nenhum: não há tela do §8 do outro lado dela.

Então a ordem é essa, e não a inversa:

1. **7×5 na DEV** — feito (#217). É onde a página do §10.3 pode ser vista e
   ajustada com o firmware novo, sem prazo emprestado da frota;
2. **7 colunas, 3 fileiras em PRODUÇÃO** pode ir quando quiserem: cabe no
   envelope, dá 4 colunas de bateria e 2 fileiras, e não quebra tela nenhuma;
3. **7×5 em PRODUÇÃO** só quando não houver mais tela do §8 em campo. **A
   condição de saída, escrita:** OTA das telas de campo para firmware
   `>= aec24c4` / `5c94c2e` — o que traz o §9 (quadrantes e `links`) e o §10
   (trilhos). Enquanto a frota não fechar esse OTA, promover a malha à produção
   é o que está proibido; mexer nela na dev, não.

O teste que reprovaria o passo 3 continua existindo, e **não foi afrouxado**:
foi partido em dois — `test_a_malha_cabe_no_teto_da_tela` (guarda o
`QD_COLS_MAX`×`QD_LINS_MAX` de vocês) e
`test_o_envelope_do_paragrafo_8_guarda_a_producao_nao_a_malha` (afirma a
incompatibilidade com o §8, em vez de deixá-la implícita). Quem guarda o passo 3
não é mais um teste unitário: é o deploy, porque é ele que escolhe o ambiente.

### 10.5 O que a tela recusa, e o que ela faz depois

Sem mudança de política: quando a malha não fecha, o quadro cai **inteiro** e a
página volta ao arranjo de antes, com o motivo no log e na faixa do topo. Três
portas, nesta ordem:

* malha acima de **7×5** — teto da tela;
* caixa de bateria abaixo de **170×125 px** — ilegível a um braço de distância.
  Acontece quando há colunas de banco demais: 6 bancos em 6 colunas de uma
  malha de 7 não fecha (o arranjo "banco · chave · banco" nunca chega lá,
  porque põe os bancos só nas colunas pares);
* qualquer peça sem célula — o tudo-ou-nada do §8.4, sem alteração.

### 10.6 Onde está, do nosso lado

`main/screen_baterias.c`: `trilhos()` e a tabela `qd_cx`/`qd_bw`/`qd_cy`/`qd_bh`
(a geometria), `QD_FINO_W`/`QD_FINO_H`/`QD_LARGO_W`/`QD_LARGO_H` e os
`_Static_assert` que provam no compilador que 7×5 é o teto. O banco de prova de
host `scripts/sim_palco.c` cobra a malha 7×5 inteira, a 4×3 de hoje, o quadro só
de chaves e as três recusas.

---

## 11. `schematic` v3: o painel de células, e a CHAVE NA ARESTA

> **Cartão #218 (quadro 29), 09/08/2026.** Este parágrafo **PEDE trabalho de
> vocês**, ao contrário do §10 — o vocabulário da posição mudou. A plataforma
> já emite a v3 na dev; a tela precisa lê-la para a página não sair errada.

### 11.1 O desenho, e por que ele mudou

O §10.3 pediu a malha 7×5 e a plataforma a entregou no mesmo dia (#217). Com o
quadro montado na bancada, o Jairo olhou e recusou o próprio pedido: o que a
página mostra é um **mar de 35 células quase uniformes**, com a comutadora
ocupando uma caixa de fileira inteira, quase do tamanho da bateria. O mockup que
ele desenhou em seguida diz outra coisa:

```
  ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐
  │bateria │   │bateria │   │bateria │   │bateria │
  └────────┘   └────────┘   └────────┘   └────────┘
       ▫            ▫            ▫            ▫
  ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐
  │bateria │   │bateria │   │bateria │   │bateria │
  └────────┘   └────────┘   └────────┘   └────────┘
       ▫            ▫            ▫            ▫
  ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐ ▫ ┌────────┐
  │bateria │   │bateria │   │bateria │   │bateria │
  └────────┘   └────────┘   └────────┘   └────────┘
```

* **4 colunas × 3 fileiras de CÉLULAS DE BANCO** — doze lugares de bateria, o
  dobro do `HC_MAX_BANKS`. A grade é FIXA: ela não cresce nem encolhe com o
  barco.
* **A chave não tem célula.** Ela mora numa **ARESTA** — o `▫` do desenho —, uma
  **caixinha pequena centrada NO VÃO** entre duas células vizinhas. Existe
  aresta entre todo par adjacente, na horizontal e na vertical: **17** no total
  (3×3 horizontais, 4×2 verticais).

O ganho não é só de tamanho. **A posição da chave passa a SER a ligação que ela
faz**: a comutadora na aresta entre BB e BE é, por construção, a que comuta BB e
BE. O desenho e os polos deixam de poder discordar.

**A consequência está assumida, e é do Jairo:** comutadora só liga bancos
**vizinhos** no painel. Quando os polos apontam para bancos que não são
vizinhos, quem avisa é o construtor da web e quem rearruma os bancos é o
operador. É como painel elétrico de verdade se desenha.

### 11.2 A régua em px NÃO mudou — a v3 cabe no motor que vocês já têm

Este é o ponto que faz o §11 barato do lado de vocês. **O painel de 4×3 células
com os vãos entre elas é a malha de 7×5 TRILHOS do §10.3**: célula de banco nos
índices PARES, vão de aresta nos ÍMPARES.

| v3 | trilho (`qd_*` do §10) |
|---|---|
| célula do banco `(col, lin)` | `(2·col, 2·lin)` |
| aresta `(col, lin, dir='h')` | `(2·col + 1, 2·lin)` |
| aresta `(col, lin, dir='v')` | `(2·col, 2·lin + 1)` |

Com 4 colunas de banco e 3 fileiras a conta dá exatamente 7×5 trilhos — o
`QD_COLS_MAX`×`QD_LINS_MAX` que os `_Static_assert` de vocês já provam. E como
**todo** trilho par carrega banco e **todo** ímpar é vão, a geometria deixa de
depender do barco: `trilhos()` roda com `largo[] = {1,0,1,0,1,0,1}` e
`{1,0,1,0,1}`, e o resultado é **constante**:

* bateria **174×127 px** — o que o §10.3 mediu.

A **caixinha da chave é a exceção, e é QUADRADA** (correção do Jairo de 09/08
18:2x, registrada no #219 do quadro 26): ela **NÃO preenche o vão**. O trilho
fino é retangular (132×104, caixa de 96×82) e a comutadora fica **centrada nele,
quadrada, do MESMO tamanho na aresta horizontal e na vertical**:

> **`QD_CHAVE = 88 px`** de lado (era 60 até o #221 — ver abaixo). **Tela e
> construtor usam ESTE número**, que é o que o pedido do #219 cobra; do nosso
> lado ele é `CAIXA_CHAVE` em `io-grade.ts`.

#### O 60 virou 88 (revisão do Jairo no vidro, #221 do quadro 26)

O 60 nunca foi medida — foi PALPITE de proporção, o "~1/3 da largura da
bateria" do mockup. Montado no vidro ele ficou pequeno demais: três linhas
(nome, lâmina, estado) espremidas, e o nome cortando com reticências. O Jairo
aprovou o painel e recusou o tamanho.

O teto de verdade **não é a margem da célula** (`QD_MARG_H/V`, que é a folga da
BATERIA — e a chave não mora em célula): **é o FIO que sai da caixinha**. Entre
a caixa da bateria e a da chave tem de sobrar **mais que um período do
tracejado (18 px)**; com 18 ou menos o trecho vira um risco sem sentido, que é a
mesma régua que o motor já cobra de todo trecho.

O eixo apertado é o **vertical**, por dois motivos: o vão é 104 px (contra 132
na horizontal) e a fileira larga é **149, ímpar** — o centro do trilho cai meio
pixel para cima no arredondamento, então descer da célula para o vão dá 127 px
de centro a centro e do vão para a célula de baixo dá **126**. Quem manda é o
126:

| lado | fio vertical | fio horizontal | veredito |
|---|---|---|---|
| 60 | 33 px | 54 px | folgado demais (o antigo) |
| **88** | **19 px** | **40 px** | **passa — e é o maior que passa** |
| 90 | 18 px | 39 px | reprova (18 não é > 18) |

Do lado da tela isso está **provado pelo compilador**, não escrito à mão:
`QD_FIO_H()/QD_FIO_V()` refazem a conta da malha com o mesmo arredondamento e
dois `_Static_assert` cobram as duas pontas — que 88 passa, e que 90 **não**
passaria (isto é, que 88 é o teto e não um número tímido).

Ganho: ~1,47× de lado, 2,15× de área. A lâmina escala de 10 para 16 px e as três
linhas ganham 28 px em cada direção — o corte de nome com reticências recua
sozinho, sem mexer nas fontes nem nos espaçamentos do #219.

A porta da "caixa ilegível" do §10.5 continua no código, mas nunca mais dispara
pela arrumação: com o painel fixo, 174×127 é maior que o mínimo de 170×125 em
todo barco. Quem pode derrubá-la é uma mudança de constante, não um operador.

### 11.3 O que muda no `/hmi/config`

**`schematic.version` = 3.** `cols`/`rows` passam a contar **células de banco**:

```json
"schematic": { "version": 3, "cols": 4, "rows": 3, "links": [ … ] }
```

As arestas **não vêm listadas** — saem da conta: `(cols-1)×rows` horizontais e
`cols×(rows-1)` verticais.

**`pos` ganha uma forma nova, só na chave.** O banco continua igual:

```json
"banks": [ { "id": "…", "pos": { "col": 0, "lin": 0 } } ]
```

A comutadora traz a célula **ÂNCORA** mais a direção do vão:

```json
{ "kind": "do", "channel": 5, "do_role": "battery_switch",
  "switch_id": "…", "pos": { "col": 0, "lin": 0, "dir": "h" } }
```

* `dir: "h"` — o vão à **DIREITA** da célula âncora (liga `col` a `col+1`);
* `dir: "v"` — o vão **ABAIXO** dela (liga `lin` a `lin+1`).

A âncora é sempre a célula de cima/à esquerda: cada vão tem um endereço só. Não
há `dir` fora da faixa — não existe `"h"` na última coluna nem `"v"` na última
fileira, porque do outro lado não há vizinha.

`links` não mudou nada (§9.4), e o `from_poles` continua separando verdade
elétrica de topologia do desenho.

**TUDO ou NADA, como sempre (§8.4):** o `schematic` só desce com TODA peça do
barco posicionada — banco com célula, chave com aresta. Chave sem `dir` conta
como **sem lugar**, e derruba o palco inteiro daquele barco.

### 11.4 O VAZIO É INVISÍVEL — e isto é metade do pedido

Correção do Jairo de 09/08 17:18, e vale a pena ler duas vezes: **ele desenhou
as 12 células e as 17 arestas no mockup só para mostrar a ESTRUTURA.**

As 12 células e as 17 arestas são **âncoras invisíveis de posição**. O que tem
peça desenha no lugar fixo dela; **o vazio é ar** — nada de contorno tênue, nada
de esqueleto, nada de grade de fundo. Na tela de bordo isso é absoluto.

(No construtor da web há uma exceção, e só uma: durante a EDIÇÃO os lugares
vazios aparecem discretos, senão não haveria onde soltar a peça. O botão
"Pré-visualizar" apaga esse andaime e mostra o que vocês vão mostrar. O modo de
visualização espelha a tela.)

**O resultado esperado com o barco da bancada** (3 bancos, 1 comutadora): BB e
BE em células vizinhas, a caixinha S6 na aresta entre elas, AI0 numa outra
célula — e **NADA mais** na página. Sem 29 retângulos vazios.

### 11.5 A v3 SUBSTITUI a v2 — não há emissão dupla

Perguntado e respondido no cartão: a plataforma **não** emite v2 para telas
velhas e v3 para novas. É uma tela só na dev, atualizada junto.

Uma `pos` com `dir` numa tela do §8 ou do §9 não tem onde pousar: ou a caixinha
cai em cima do banco da âncora, ou não cai em lugar nenhum. Isso não é novidade
— é o mesmo problema que a malha 7×5 já tinha —, e **quem segura é o AMBIENTE,
não o emissor**: as telas em campo falam com a PRODUÇÃO (`api.marinetcs.com`) e
este palco só existe na DEV (`api-dev`).

O §10.4 continua sendo a porta do rollout de produção, agora com a condição de
saída somada: OTA das telas de campo para firmware `>= aec24c4` / `5c94c2e` **e**
leitura da v3. Quem guarda a porta é o deploy.

**Recusa recomendada do lado de vocês:** `version` que a tela não conhece →
derruba o quadro INTEIRO e volta ao arranjo de antes, com o motivo no log e na
faixa do topo. É a mesma política do §10.5, e é o que faz uma plataforma à
frente do firmware ser um desenho velho em vez de um desenho errado.

### 11.6 O que pedimos do lado de vocês (cartão irmão no quadro 26)

1. **Ler `schematic.version == 3`** e tratar `cols`/`rows` como células de
   banco, traduzindo para os trilhos pela tabela do §11.2. A `trilhos()` de
   vocês não muda — muda quem a chama.
2. **Ler `pos.dir`** na chave e desenhar a caixinha **no vão**, centrada, no
   tamanho fixo e QUADRADO de **88×88 px** (§11.2 — era 60 até o #221; a tela
   já está em 88) — não o vão inteiro.
3. **Não desenhar lugar vazio** (§11.4). Nem célula, nem aresta, nem contorno.
4. **Recusar `version` desconhecida** derrubando o quadro inteiro (§11.5).
5. Opcional, e nosso palpite de que ajuda: quando a chave está no vão dos polos
   dela, o fio banco→chave→banco fica CURTO e reto por construção. Vale
   desenhá-lo com a espessura do barramento em vez do traço fino — é a leitura
   que o eletricista faz de longe.

**A pergunta do #219 sobre a aresta VAZIA, respondida.** "Aresta vazia entre
bancos ligados por fio desenhado = fio direto atravessando a caixinha vazia, ou
a caixinha some e vira traço?" — **a caixinha não existe**. Pelo §11.4, aresta
sem peça é ar: o que passa ali é o `links` (§9.4), desenhado como traço direto
entre as duas células. Do lado do construtor a única diferença é o GESTO: no
modo "Ligar peças", um toque no vão vazio entre dois bancos desenha esse fio
direto sem precisar tocar as duas caixas. O que ele grava é a mesma ligação do
§9.4, com `from_poles: false` — nada de novo desce por causa disso.

### 11.7 `config_version`

Muda sozinho: `version`, `cols`, `rows` e cada `pos` entram no corpo que gera o
hash. A tela rebaixa a config no ciclo normal, sem nada especial.

### 11.8 Onde está, do nosso lado

* `matel/services/esquema_eletrico.py` — `MALHA_COLUNAS`/`MALHA_FILEIRAS` (4×3),
  `TRILHOS_COLUNAS`/`TRILHOS_FILEIRAS` (7×5, o espelho do §11.2),
  `aresta_na_malha`, `celulas_da_aresta`, `aresta_entre`, `arestas_do_painel`,
  `lugar_do_canal`, `posicao_do_canal` e `aresta_dos_polos`;
* `SCHEMATIC_VERSION = 3` no mesmo módulo, emitido por
  `matel/services/hmi_config.py` — que também LOGA a chave cujos polos não são
  vizinhos, ou que está no vão errado;
* migração `092_painel_de_arestas` — a coluna `esquema_dir` e a **conversão** do
  que a malha 7×5 gravou, pela tabela do §11.2 (trilho par → célula, ímpar →
  aresta); o que não converte volta para a bandeja;
* `apps/nautica/src/lib/api/io-grade.ts` e
  `components/iot/EsquemaEletricoBuilder.tsx` — o construtor, com os dois fluxos
  do cartão: pousar a chave num vão **define** os polos, e escolher os polos
  **acende** o vão em que ela cabe;
* testes: `tests/test_grade_do_esquema.py` e `apps/nautica/tests/io-grade.test.ts`
  — inclusive a régua dos 174×127 e a conversão da 092.

## 12. A chave que NÃO liga banco a banco: a BORDA do painel

> **Cartão #230 (quadro 29), 09/08/2026.** Este parágrafo **PEDE trabalho de
> vocês**, como o §11: há um lugar novo a ler. A plataforma já emite na dev.

### 12.1 O buraco, e como ele apareceu

O §11 deu à comutadora um lugar exato — a **aresta**, o vão entre duas células
vizinhas — e com isso a posição virou a ligação. Só que a aresta pressupõe
**duas** baterias, uma de cada lado do vão, e **nem toda chave comuta duas**:

| papel | quantos bancos toca | o outro lado é |
|---|---|---|
| `start_parallel` | 2 | outra bateria |
| `emergency_crossover` | 2 | outra bateria |
| **`house_master`** | **1** | o **barramento** de serviço |
| **`shore_charger`** | **1** | o **cais** |

Os dois de baixo não tinham onde morar. Em 09/08 às ~21h05 o Jairo criou a
chave **"Cais"** (`do3`, `shore_charger`) e ela ficou na bandeja do construtor,
sem lugar possível — e o **tudo-ou-nada do §11.3** fez o resto: com uma peça sem
posição, **o `schematic` do barco inteiro parou de descer** (`pela metade: do3`
no log da emissão). O aviso estava certo; o que faltava era o operador ter como
resolvê-lo.

### 12.2 A `pos` da chave de fronteira: célula de BORDA + face

Chamamos de **chave de fronteira** a que serve UM banco. Ela mora numa **célula
de borda do painel**, e a `pos` traz essa célula mais a **FACE** por onde o fio
deixa o quadro:

```json
{ "kind": "do", "channel": 3, "do_role": "battery_switch",
  "switch_role": "shore_charger", "switch_id": "…",
  "pos": { "col": 0, "lin": 1, "dir": "e" } }
```

* `dir: "c"` — sai por **cima**; só na fileira 0;
* `dir: "b"` — sai por **baixo**; só na última fileira;
* `dir: "e"` — sai pela **esquerda**; só na coluna 0;
* `dir: "d"` — sai pela **direita**; só na última coluna.

São **14 bordas**: 4 em cima, 4 embaixo, 3 de cada lado. A célula de canto entra
duas vezes, com faces diferentes — da quina se sai por qualquer uma das duas
bordas que a tocam.

**As quatro letras são NOVAS de propósito, e não reaproveitam `h`/`v`.** Um `h`
na última coluna e um `d` na última coluna seriam o mesmo endereço com dois
sentidos, e a leitura de `pos.dir` deixaria de ser única. Quem decide qual
alfabeto vale é o **PAPEL**: comutadora lê `h`/`v`, chave de fronteira lê
`c`/`b`/`e`/`d`, e **cada uma recusa a direção da outra** — a peça cai na
bandeja e o operador rearruma, que é a mesma política do §11 com a malha antiga.

### 12.3 Por que na CÉLULA, e não "na aresta externa" — a conta

A proposta do cartão era pôr a caixinha na *aresta externa da célula do banco
servido*. **Ela não cabe**, e a régua do §11.2 é que diz:

1. **Fora do painel não há pixel.** Os 7×5 trilhos preenchem o QUADRO inteiro:
   `4·210 + 3·132 = 1236` e `3·149 + 2·104 = 655`. Não sobra moldura.
2. **Dentro da célula do banco só há a margem**, que é a folga da bateria: 18 px
   na horizontal e 11 na vertical. Não comporta a caixinha de 88, e **nem um
   fio maior que o período do tracejado** (18) — a mesma régua que deu o teto
   dos 88 no #221.
3. **Abrir uma faixa de borda no painel derruba a bateria.** Com uma faixa fina
   a mais em cada eixo, o trilho largo cai de 210×149 para 144×79 e a caixa da
   bateria para **108×57** — abaixo do mínimo legível de 170×125, e pelo §10.5 a
   tela **recusa o quadro inteiro**.

Na **célula de borda**, ao contrário, a conta fecha com folga. A caixinha de 88
centrada no trilho largo deixa de fio para fora:

| face | trilho | fio para fora | veredito |
|---|---|---|---|
| `e` / `d` | 210 | **61 px** | passa |
| `c` / `b` | 149 | **30 / 31 px** | passa |

Contra os 18 px do tracejado, folgado nos dois eixos. **A régua do §10/§11
continua intacta** — nenhuma constante mudou, e a bateria segue em 174×127 em
todo barco.

**O preço, e ele é explícito: a chave de fronteira COME a célula.** Onde ela
pousa não pousa banco. Cabe sem aperto — 12 células para no máximo 6 bancos mais
2 chaves de fronteira (o vocabulário dá **uma vaga por papel**, §2).

### 12.4 O CONTRATO dos polos: um só, e o outro é nulo

`shore_charger` e `house_master` passam a ter **um polo**:

* **`switch_bank_a`** — o **banco servido**. É dele que sai o fio até a
  caixinha.
* **`switch_bank_b`** — **vazio por definição do papel**. O outro lado é o cais
  ou o barramento, e esse não é canal deste barco.

No corpo do save os dois campos continuam andando **em par** (a API recusa um
sozinho): trocar uma comutadora em `shore_charger` manda `switch_bank_b: null`
junto, e é isso que impede o polo do papel anterior de ficar para trás
desenhando um fio que a chave não faz mais.

**A validação do §11 ganha o par dela.** Lá a chave tinha de estar no vão dos
dois bancos que comuta; aqui a **célula da borda tem de ENCOSTAR na célula do
banco servido**. Não encostando, o construtor avisa (`longe_do_banco`) e leva a
caixinha com um clique para uma borda livre ao lado do banco — o fio
atravessando o painel faria a posição parar de dizer quem a chave alimenta.

### 12.5 O que muda no desenho de vocês

1. **Ler `pos.dir` de quatro letras novas** (`c`/`b`/`e`/`d`) e desenhar a
   caixinha **centrada na CÉLULA** daquela `pos` — trilhos `(2·col, 2·lin)`,
   os mesmos do banco —, no tamanho fixo e quadrado de **88×88**, o mesmo do
   §11.2. Não é o trilho inteiro: ela fica no meio dele.
2. **Desenhar o FIO CURTO para fora**, da borda da caixinha até a borda do
   QUADRO, na face que `dir` diz. Comprimentos da tabela do §12.3.
3. **Não desenhar caixa nenhuma para o cais nem para o barramento** — eles ficam
   implícitos fora do quadro. Nosso palpite de leitura, e é o que o construtor
   faz: um risco atravessado na moldura, como um borne de barramento se lê num
   unifilar de longe.
4. **O fio do banco servido até a caixinha é um fio comum** — ele vem no
   `links` como qualquer outro, com as duas pontas sendo o banco e a chave.
   Nada de novo desce por causa dele.
5. **`version` continua 3.** `cols`/`rows` não mudaram e as bordas **não vêm
   listadas** — saem da conta, como as arestas: são as células com `col` 0 ou
   `cols-1`, ou `lin` 0 ou `rows-1`. Uma tela do §11 que não conheça as letras
   novas cai na recusa do §11.5 (derruba o quadro inteiro), e o AMBIENTE segura
   o resto: isto só existe na `api-dev`.

### 12.6 Onde está, do nosso lado

* `apps/nautica/src/lib/api/io-esquema.ts` — `PAPEIS_DE_FRONTEIRA` e
  `ehDeFronteira`, o complemento exato de `PAPEIS_DE_DOIS_POLOS`;
* `apps/nautica/src/lib/api/io-grade.ts` — `Fronteira`, `BORDAS`,
  `bordaNoPainel`, `FRONTEIRAS` (as 14), `celulaOcupada` (a disputa de trilho),
  `espacoDaPeca`/`lugarAceita` (os três espaços) e **`fioDaBorda`**, que é a
  conta do §12.3 em código;
* `apps/nautica/src/components/iot/EsquemaEletricoBuilder.tsx` — o construtor:
  a borda só acende com a chave de fronteira na mão, escolher o banco servido
  ACENDE as bordas livres ao lado dele, e pousar a caixinha ao lado de um único
  banco DEFINE o banco servido;
* `apps/nautica/tests/io-grade.test.ts` — inclusive o teste que prova os 30 px
  de fio e o que reconstitui o barco do Jairo fechando o painel com o "Cais".
