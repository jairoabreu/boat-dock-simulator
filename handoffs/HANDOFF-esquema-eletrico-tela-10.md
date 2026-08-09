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
| colunas | 4 |
| fileiras | 3 |
| quadrante | 320 × 267 px |

**4×3, e a escolha está feita** — pelo Jairo, em 09/08/2026 (#209). A primeira
proposta era 4×2, e a ressalva contra ela era a capacidade: o firmware aceita 6
bancos e 6 chaves — 12 peças —, e 4×2 tem 8 quadrantes. Barco com mais de 8
peças não fecharia o palco, e pelo tudo-ou-nada do §8.4 isso significaria **nada
descer**. 4×3 dá 12 quadrantes, **exatamente o teto do firmware**: nenhum barco
que vocês aceitam fica sem lugar, e a conta deixa de estar em aberto.

Note que a escolha não some do código: `MALHA_COLUNAS`/`MALHA_FILEIRAS` em
`esquema_eletrico.py`, com gêmeos em `io-grade.ts`, continuam sendo os dois
números que a definem. Trocá-la de novo é trocá-los — sem migração e sem mexer
neste contrato, desde que a nova divisão respeite o §9.7 —, e o construtor
continua dizendo na cara quantas peças passariam do que a malha comporta.

Um efeito da divisão vale dito: o arranjo automático do construtor põe 2 bancos
e a chave entre eles por fileira, então com 4 colunas uma corrente de 3 bancos
não cabe numa fileira só — ela transborda para a sobra. É a mesma conta de
antes; o que mudou é que agora há fileira para onde transbordar.

O que a escolha tem de respeitar, dos dois lados, está no §9.7.

### 9.3 O que muda no `/hmi/config`

**`schematic` ganha `version` e `links`:**

```json
"schematic": {
  "version": 2,
  "cols": 4,
  "rows": 3,
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

**E isso funciona por uma escolha deliberada: a malha de quadrantes cabe dentro
da grade 7×3 do §8.** Todo `pos` que desce hoje (coluna 0..3, fileira 0..2) é
uma célula válida para a `esquema_por_config()`, que continua centrando o bloco
no palco como sempre. A tela de hoje desenha o barco arrumado em quadrantes
como se fosse a grade dela, com menos colunas ocupadas.

**A regra, escrita para quem for mexer:** qualquer divisão de quadrantes futura
tem de caber em `CEL_MAX`×`LIN_MAX` enquanto houver tela do §8 em campo. 4×2 e
4×3 cabem. 4×4 **não** cabe, e escolhê-la exige aposentar o §8 primeiro. Do
nosso lado isso está guardado por teste (`test_a_malha_cabe_no_envelope_do_`
`paragrafo_8`), não por comentário.

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
