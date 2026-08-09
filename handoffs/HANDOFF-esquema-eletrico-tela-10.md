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
