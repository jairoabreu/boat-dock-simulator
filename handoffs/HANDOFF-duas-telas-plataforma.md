# Handoff — DUAS TELAS no mesmo casco: o contrato da plataforma

**Data:** 11/08/2026
**De:** plataforma web (`matel-web-platform-api` + `MaTel-web_platform`)
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)
**Responde a:** `matel-ivs-display-p4/docs/ANALISE-multiplas-telas.md` §5
(cartão #249, quadro 26 — item 3 da ordem recomendada de lá)
**Cartão:** #254 (quadro 29 — Plataforma Web MarineTelematics)

> **Resumo em uma linha:** as quatro perguntas do §5 estão respondidas, e o que
> antes funcionava por SUPOSIÇÃO virou promessa: o segundo inventário idêntico
> confirma em vez de refazer, a resposta passou a trazer `config_version` e
> `hmi_peers`, e duas telas legítimas são DOIS cadastros — o `self_mac_matches`
> continua significando exatamente o que significava.
>
> **Mudança de firmware necessária: nenhuma.** Os dois campos novos são
> aditivos, e uma tela que os ignore se comporta como hoje. O que eles compram
> está no §6.

---

## 0. As quatro decisões, de uma vez

| § da análise | Pergunta | Decisão |
|---|---|---|
| 1 | O segundo POST idêntico conta `matched` ou refaz `renumbered`/`learned`? | **`matched`.** Os contadores são do que AQUELA requisição mudou. A segunda tela não repete trabalho e recebe `config_changed: false` |
| 2 | `config_changed` volta `true` para as duas? | **Não, e nunca voltou** — ele é EVENTO. Mas faltava o outro lado: a tela que NÃO mudou nada agora recebe `config_version`, e é assim que ela descobre a mudança que a colega causou |
| 3 | Uma embarcação pode ter dois cadastros de HMI? | **Pode, e DEVE: um cadastro por tela.** É o que faz `self_mac_matches` continuar querendo dizer "este token é desta tela". A resposta passou a trazer `hmi_peers` |
| 4 | Recorte de config por tela (salão ≠ flybridge)? | **Fica como evolução.** O padrão continua "tudo para todas". O motivo, e o que teria de mudar, no §5 |

---

## 1. Idempotência — o segundo inventário CONFIRMA

**A regra, escrita:** os contadores de `POST /hmi/inventory` descrevem **o que
esta requisição mudou no cadastro** — não o que existe no barramento. Quem quer
o retrato do barramento pede `/hmi/config`.

Consequência para duas telas mandando a MESMA lista:

| Campo | Tela A (chegou primeiro) | Tela B (segundos depois) |
|---|---|---|
| `matched` | 0 | **2** |
| `created` | 2 | 0 |
| `learned` / `renumbered` | 1 / 0 | 0 / 0 |
| `config_changed` | `true` | **`false`** |

É isso que impede a tela B de rebaixar a config inteira por trabalho alheio.
O casamento é por **UIN**, e o UIN da placa é o mesmo nas duas telas — quem
chega depois encontra o cadastro que a primeira criou e apenas o confirma.

**A janela que faltava.** Havia um caso em que as duas se atropelavam de
verdade: as duas leem "esta placa não existe" no mesmo instante, as duas criam,
e o índice único do banco recusa a segunda. Antes isso virava **409** e a tela
esperava o poll seguinte (5 min) para convergir — o 409 estava certo em não ser
500, mas era um erro onde não havia erro nenhum.

Agora o passe é **refeito uma vez**, releitura do casco inclusive: na segunda
leitura o cadastro da colega já está commitado, e a resposta sai **2xx com
`matched`**. O 409 sobra para o conflito que se REPETE — esse não é corrida, é
cadastro errado (a mesma placa em dois barcos, por exemplo), e continua sendo
resolvido pelo operador na Automação IoT.

**O que a tela deve fazer:** nada. Continue mandando a lista inteira do que o
seu barramento enxerga, no seu ritmo, sem coordenar com a outra tela.

---

## 2. `config_version` na resposta do inventário — como B sabe do que A fez

**O problema real não era o `config_changed` voltar `true` para as duas** (ele
nunca voltou: é derivado dos contadores DAQUELA requisição). Era o inverso — a
tela que não causou a mudança **não fica sabendo dela** pelo inventário, e só
descobre no poll seguinte de `/hmi/config`.

A resposta ganhou um campo de **ESTADO**, ao lado do de evento:

```jsonc
{ "received": 2, "matched": 2, "created": 0, "renumbered": 0,
  "learned": 0, "unidentified": 0, "conflicting": 0,
  "config_changed": false,      // EVENTO: o que ESTE POST mudou
  "config_version": 97,         // ESTADO: em que versão a config do casco está
  "self_mac_matches": true,
  "hmi_peers": 1,               // quantas OUTRAS telas este casco tem
  "at": "2026-08-11T12:44:55Z" }
```

`config_version` é o mesmo inteiro do `/hmi/config` (o da NVS). Diferente do que
a tela guarda → vale puxar a config, mesmo com `config_changed: false`.

**Duas ressalvas honestas, porque elas mudam o que se pode concluir do número:**

1. Ele pode estar **um passo atrás** do conteúdo. Quem incrementa a versão é o
   `GET /hmi/config` — se ninguém pegou a config depois da mudança, o número
   ainda é o velho. Ele **acelera** a descoberta; **não prova** que nada mudou.
   Quem prova continua sendo o GET com `If-None-Match` (e o piso de 304 do §5.1
   do handoff da HMI segue valendo, por equipamento).
2. Ele é do **casco**, não da tela. Com o recorte por tela do §5 isso mudaria —
   e é justamente por isso que ele não entra agora.

**O que a tela deve fazer:** se já guarda `config_version` na NVS (guarda),
comparar com este campo depois de cada inventário e puxar `/hmi/config` quando
diferir. Ignorar o campo mantém o comportamento de hoje, que também converge —
só que no ritmo do poll.

---

## 3. Duas telas são DOIS cadastros

**Decisão: um cadastro por tela, sempre.** Cada tela é um `device` próprio, com
o seu token `mtd_…` e o seu `hw_id` (o MAC do C6). Não existe "cadastro da
embarcação" compartilhado pelas duas, e não há limite de telas por casco na
plataforma.

Isso é o que preserva o `self_mac_matches`. Ele nunca perguntou "esta tela é a
tela do barco?" — ele pergunta **"o token que estou usando foi emitido para ESTA
tela?"**. Com um cadastro por tela ele é `true` nas duas: **duas telas legítimas
não geram alarme falso**. Ele continua sendo o que apontou o cadastro errado da
bancada em 09/08.

O erro que sobra é o inverso, e agora ele tem nome no log: **um cadastro gravado
em duas telas**. Aí o mesmo `device_id` reporta MACs diferentes a cada ciclo, o
`self_mac_matches` pisca entre `true` e `false`, e nenhum POST isolado diz qual
das duas está errada — porque as duas mandam a mesma coisa. A plataforma compara
com o MAC anterior do MESMO cadastro e registra:

```
hmi.inventory.token_em_duas_telas   device_id=… cadastro=AABBCCDD0254
                                    de=AABBCCDD0254 para=1020BAF3C8E4
hmi.inventory.mac_divergente        device_id=… cadastro=… reportado=…
```

O primeiro é token clonado; o segundo, isolado, é token gravado na tela errada.

### `hmi_peers` — a tela passa a saber que não está sozinha

Quantos **outros** cadastros de tela existem neste casco. `0` = é a única do
barco (o parque de hoje inteiro). Conta **cadastro, não presença**: tela
desligada continua sendo tela do casco, senão o número dançaria a cada boot.

É a informação que só a plataforma tem, e é ela que fecha o buraco do §3 da
análise: o estado que a tela guarda por conta própria — tempo morto de inversão
do guincho, livro-caixa de alarmes, amarra integrada, pendência de reenvio — só
é seguro **enquanto ela for a única**. Com `hmi_peers > 0` o firmware pode
escolher o caminho conservador sem que ninguém precise cadastrar isso à mão.

> **Aviso de cadastro.** `hmi_peers` conta quem está com `model = "ivs-hmi10"`.
> A tela da bancada em dev estava com o `model` **vazio** (o operador não
> escolheu o tipo no cadastro), e com isso um casco de duas telas responderia
> "sozinha" por causa de um campo em branco. Por isso o cadastro que chega ao
> `POST /hmi/inventory` sem `model`, com `hw_kind='mac'` e `self_mac`, **passa a
> se marcar sozinho** como tela — quem fala o protocolo da tela é uma tela. Só
> preenche buraco: `model` já escrito nunca é sobreposto.

---

## 4. O que continua igual (e é de propósito)

- **`/hmi/config` é da EMBARCAÇÃO.** As duas telas recebem o mesmo corpo, o
  mesmo ETag e a mesma `config_version`. Nada per-tela entrou no corpo da
  config — ver o §5.
- **Cada tela tem o seu ETag e o seu piso de 304**, porque o registro é por
  equipamento. Uma tela que perdeu o asset volta a receber corpo sem arrastar a
  outra.
- **`GET /hmi/state` não mudou.** Ele é do casco, e as duas telas leem o mesmo
  snapshot.
- **O endereço CAN (`node_id`) continua sendo observação, não cadastro.** Se as
  duas telas reportarem endereços diferentes para o mesmo UIN (uma viu a placa
  antes da rearbitragem), **ganha a última a falar** — a identidade manda e a
  config vai junto. Não há empate a resolver: as duas convergem no ciclo
  seguinte porque leem o mesmo barramento.

---

## 5. Recorte de config por tela — FICA COMO EVOLUÇÃO

Salão e flybridge querendo páginas diferentes é um pedido legítimo e previsível
(a tela de fora não precisa da página de bombas). Não entra agora, e o motivo
não é preguiça — é onde o custo cai:

**Hoje `config_version` e o ETag são o hash do CONTEÚDO DA EMBARCAÇÃO.** É essa
igualdade que sustenta a promessa "mudou o cadastro → chega ao barco", e foi ela
que matou a classe de bugs do provisionamento pelo celular. Recorte por tela
transforma os dois em `(embarcação × papel da tela)`: dois hashes, duas versões,
e a pergunta "esta tela está em dia?" deixa de ter uma resposta só. Trocar isso
por uma preferência de layout, antes de existir um barco com duas telas em
operação, é caro na peça errada.

**Se e quando entrar, entra assim** (registrado para não se reinventar depois):

- O papel/lugar é **opcional** e mora no cadastro da tela (`devices`), não na
  embarcação — é a tela que está no flybridge, não o barco.
- O padrão continua **"tudo para todas"**: cadastro sem papel recebe a config
  inteira, exatamente como hoje. Nenhuma tela em campo muda de comportamento.
- O recorte é **subtrativo** e por área/página: a config da tela é a do casco
  menos o que o papel dela esconde. Nunca conteúdo diferente — só menos.
- `config_version` e ETag passam a ser **por (embarcação, papel)**, e o handoff
  da HMI (§5.1) precisa dizer isso explicitamente antes de a primeira tela
  recortada existir.

Até lá: **as duas telas mostram tudo**, e isso está certo como padrão.

---

## 6. O que a tela deve fazer

**Obrigatório: nada.** Os dois campos são aditivos e uma tela que os ignore se
comporta como hoje.

**Recomendado, em ordem de valor:**

1. **Comparar `config_version` do inventário com a NVS** e puxar `/hmi/config`
   quando diferir. É como a tela B descobre, em um ciclo em vez de dois, a placa
   que a tela A acabou de cadastrar.
2. **Ler `hmi_peers`** e guardá-lo. Ele é a licença para o firmware tratar como
   local o estado que hoje é local por omissão. Com `> 0`, valem os itens 1, 2 e
   4 da ordem recomendada da análise (tempo morto do guincho, reconhecimento de
   alarme em broadcast, desistência da pendência de reenvio).
3. **Mostrar os dois na página de diagnóstico.** "2ª tela do casco, config v97"
   responde sozinha o "na de baixo funciona" do §5 da análise.

**E um pedido de cadastro, não de código:** cada tela precisa do **seu** token.
Clonar a imagem de provisionamento de uma tela na outra é o caso que o
`token_em_duas_telas` acusa — e nesse estado o `self_mac_matches` não tem como
dizer a verdade sobre nenhuma das duas.

---

## 7. O que este handoff NÃO resolve

A análise foi clara sobre onde mora o perigo, e não é aqui. A plataforma não
alcança nada disto — são todos estado interno da tela, em barramento offline:

| Item | Onde se resolve |
|---|---|
| **Tempo morto de inversão do guincho** não é avaliado na 2ª tela | módulo (contrato novo com o iVS2008) — §3 da análise |
| **Amarra integrada só por quem comandou** | tela: integração PASSIVA pelo relé confirmado — §3(b) |
| **Reconhecimento de alarme não viaja** | quadro MTCP novo em broadcast — §4 |
| **Relé bate-e-volta** (duas pendências opostas) | `c6_link.c`: desistir quando outro mestre fala — §2 |
| **OTA divergente entre as duas** | a plataforma não versiona firmware de tela hoje |

Os dois primeiros encostam em caminho certificado e não devem ir ao barco sem
bancada com duas telas e dois módulos, como a própria análise pede.

---

## 8. Onde está, do nosso lado

Repo `matel-web-platform-api`:

| O quê | Onde |
|---|---|
| Retentativa do passe, marca de tela, logs de MAC | `matel/routers/hmi.py` — `post_hmi_inventory`, `_passe_do_inventario`, `_anota_mac` |
| `hmi_peers` e `config_version` (leitura pura) | `matel/services/hmi_config.py` — `telas_irmas`, `versao_publicada`, `MODELO_TELA` |
| Campos novos na resposta | `matel/schemas/hmi.py` — `HmiInventoryOut` |
| Testes | `tests/test_inventario_hmi.py` — bloco "Duas telas no mesmo casco (#254)" |

Validado em `api-dev.marinetcs.com` com dois cadastros de tela no casco da
bancada (NX 50 Invictus — Demonstração): segundo inventário idêntico devolveu
`matched: 2, created: 0, config_changed: false, config_version: 97`; o cadastro
sem `model` se marcou sozinho; e a alternância de `self_mac` no mesmo cadastro
apareceu no log como `token_em_duas_telas`.

Nada de migração: `hmi_peers` sai de `devices.model`, e `config_version` já
existia em `vessels`.
