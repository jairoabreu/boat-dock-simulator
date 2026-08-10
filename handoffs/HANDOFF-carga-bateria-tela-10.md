# Handoff — a plataforma passou a mandar a RÉGUA DE "CARREGANDO"

**Data:** 09/08/2026
**De:** plataforma web (`matel-web-platform-api` + `MaTel-web_platform`)
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)
**Segue:** `HANDOFF-esquema-eletrico-tela-10.md` (09/08/2026, cartão #190)
**Cartão:** #191 (quadro 29 — Plataforma Web MarineTelematics)

> **Resumo em uma linha:** o `banks[]` do `/hmi/config` ganhou `charge`
> (`on_v`, `off_v`, `sustain_s`) — a régua, **por química e já escalada**, que
> diz se aquele banco está sendo carregado só pela TENSÃO. E o
> `nominal_voltage`, que sempre saiu `null`, **passou a vir preenchido** quando
> o operador o cadastra.
>
> **Firmware a fazer:** parsear o `charge` para o `hc_bank_t` e usá-lo na
> pílula de estado quando **não há shunt** (`!L.tem_a`) — hoje ela diz "SEM
> MONITOR" em 100% dos barcos do parque, porque shunt não existe em nenhum.

---

## 1. Por que isto existe

Não há shunt a bordo. O que existe é a tensão do banco, medida no borne pelo
iVS2408 e escalada pelo canal (`ai_role: "battery"`). Dela dá para dizer que há
uma **fonte ligada** — alternador, carregador de cais, solar —, porque uma
fonte empurra o banco acima da tensão que ele teria sozinho.

O que ela **não** diz: quanta corrente entra. Um banco "carregando" a 13,4 V
pode estar recebendo 60 A ou 0,5 A. Por isso a regra do §4: **onde há corrente,
a corrente vence.**

---

## 2. O campo novo

```json
"banks": [
  { "id": "3f1c…-a92b", "name": "Serviço", "chemistry": "lifepo4",
    "bank_role": "house", "nominal_voltage": 12, "capacity_ah": null,
    "charge": { "on_v": 13.8, "off_v": 13.55, "sustain_s": 20.0 } }
]
```

| Campo | Significado |
|---|---|
| `on_v` | **volts de banco.** Sustentado neste valor **ou acima**, o banco está sendo carregado. |
| `off_v` | a histerese: uma vez carregando, só se sai **abaixo** disto. Sempre `< on_v`. |
| `sustain_s` | por quantos segundos a condição precisa valer antes de virar estado — **nos dois sentidos**. |

**Já vem RESOLVIDA.** Química aplicada, sobreposição do cadastro daquele barco
aplicada, e **escalada pela nominal**: num banco de 24 V o `on_v` já chega
26,8. A tela não precisa da tabela nem de nenhuma conta — compara com a mesma
tensão que ela já pinta.

`charge` é **`null`** quando não há como julgar (banco sem química cadastrada e
sem régua própria). É o mesmo silêncio do `chemistry`: nesse caso, **siga com o
que já sabe** (a pílula da corrente, ou "SEM MONITOR"). Não invente um limiar —
é justamente o erro que o §3 descreve.

### 2.1 `nominal_voltage` deixou de sair nulo

O handoff do #190 listava `nominal_voltage` como "sem cadastro, sai `null`".
**Mudou:** o campo ganhou cadastro na plataforma (lista fechada: 6, 12, 24, 36,
48 V). O `hmi_cloud.c:635` já o converte para `nominal_dv` — **nada a fazer no
firmware**, mas saibam que a curva de repouso de `soc_por_tensao()` vai começar
a escalar de verdade nos barcos de 24 V, e não mais tratar todos como 12 V.

`capacity_ah` continua nulo: esse ainda não tem cadastro.

---

## 3. Por que a régua é por química — o erro que ela evita

A tensão de **repouso** de um banco cheio muda com a química, e é ela que o
limiar precisa deixar para trás:

| | repouso cheio | float do carregador | limiar escolhido |
|---|---|---|---|
| inundada | ≤ 12,7 V | 13,5–13,8 | **13,2 V** |
| AGM | ≤ 12,9 V | 13,6–13,8 | **13,4 V** |
| gel | ≤ 12,9 V | 13,2–13,5 | **13,3 V** |
| LiFePO4 | ≤ 13,4 V | 13,4–13,6 | **13,8 V** |

Um LiFePO4 cheio, parado, na boia, mora em **13,3–13,4 V** — **acima** do
limiar de uma chumbo inundada. Com uma régua só, o estado de um banco de lítio
acenderia no dia da instalação e nunca mais apagaria. Foi o alerta que originou
o cartão.

O **gel não herda da AGM**: o float dele é mais baixo (sensível a calor), e com
13,4 um carregador floatando em 13,3 passaria despercebido.

**Ressalva honesta, e é do LiFePO4:** em lítio o repouso cheio (13,3–13,4) e o
float recomendado (13,4–13,6) se **sobrepõem** — não existe limiar que os
separe. Os 13,8 V põem a detecção na região de absorção, onde a fonte é
inequívoca. O preço, escolhido: **lítio em float não aparece como carregando.**
O erro que se evita (estado verde permanente num banco que está descarregando)
é muito pior que o que se aceita.

Os números e as fontes de mercado estão por extenso em
`matel/services/carga_bateria.py` — é lá que se mexe se a régua mudar, e a
mudança desce por `/hmi/config` sem firmware novo.

---

## 4. Como usar na tela (a proposta, e o porquê de cada regra)

**Regra 1 — onde há corrente, a corrente vence.** A pílula de
`screen_baterias.c:822` sai do `L.a` e deve continuar saindo. Corrente é
medição; tensão é inferência. No dia em que o `battery_current` existir, a
inferência sai de cena naquele banco sem ninguém mexer.

**Regra 2 — sem corrente e com `charge`, infira.** É o caso de **todo o parque
de hoje**: `!L.tem_a` cai em "SEM MONITOR", que é verdade mas não ajuda. Com a
régua descendo, esse mesmo banco pode dizer "CARREGANDO" ou "SEM CARGA".

**Regra 3 — sem corrente e sem `charge`, "SEM MONITOR" como hoje.** Não chutar
é o comportamento correto.

**Regra 4 — os dois filtros são obrigatórios, e cada um mata um defeito
diferente:**

* **histerese** (`off_v`): uma vez carregando, só se sai abaixo de `off_v`.
  Sem ela um banco em float parado no limiar reescreve a pílula a cada leitura;
* **sustentação** (`sustain_s`): a condição vale por esse tempo antes de virar
  estado, **nos dois sentidos**. Sem ela, cada partida de motor pisca
  "CARREGANDO". Simétrica de propósito — uma pílula que acende rápido e apaga
  devagar conta duas histórias sobre o mesmo barco.

**Regra 5 — o terceiro estado não desenha afirmação.** Enquanto a sustentação
ainda conta, ou quando a leitura sumiu, o veredito é "não sei" — e "não sei"
**não é "sem carga"**. Um selo cinza dizendo "sem carga" manda alguém procurar
um carregador que talvez esteja ligado.

A máquina de estados inteira, com esses cinco pontos, tem duas implementações
de referência já verdes que dá para ler como pseudocódigo:
`matel/services/carga_bateria.py` (`avaliar`) e
`apps/nautica/src/lib/api/io-carga.ts` (`avancarCarga`).

### 4.1 O unifilar

O #104 já anima fluxo por aresta, e hoje o **sentido** sai da corrente medida —
que não existe em nenhum barco. Com "carregando" inferido, o trecho que hoje
pinta liso ganha sentido: **fluxo entrando no banco** enquanto a régua diz
carregando. É a metade da entrega que pedimos ao lado de vocês.

---

## 5. O que a plataforma faz com isso do lado dela

Para vocês saberem onde o veredito já aparece (e por que ele pode divergir do
de vocês por alguns segundos):

* **badge no card do banco**, na Automação IoT, com a mesma régua e a mesma
  máquina, sobre a leitura ao vivo;
* **contexto no alerta de bateria baixa**: "abaixo do mínimo, mas CARREGANDO"
  se resolve sozinha; "abaixo do mínimo e SEM CARGA" é alguém que precisa ir
  até o barco hoje. No teto não vai contexto nenhum — sobretensão **já é** a
  fonte em fuga.

O worker da nuvem amostra a cada 60 s; vocês leem o barramento em segundos. **A
tela é a de resolução mais fina, e é a única que julga OFFLINE** — o badge da
plataforma depende de conectividade, o de vocês não. É por isso que a régua
desce em vez de descer só o veredito.

---

## 6. `config_version` e tetos

Nada a fazer: a versão é o hash do corpo, então o campo novo a faz subir
sozinha na primeira leitura de cada barco. `HC_MAX_BANKS` = 6 segue valendo.

---

## 7. Onde está, do nosso lado

* Migração `087_carga_bateria` — `nominal_voltage` e `charge_rule` em
  `io_channels`.
* `matel/services/carga_bateria.py` — a tabela por química, a resolução da
  régua e a máquina de estados. **É o arquivo a mexer se a régua mudar.**
* `matel/services/esquema_eletrico.py` — a emissão do `charge` no banco.
* `matel/schemas/hmi.py` — o contrato (`HmiBankCharge`).
* `matel/realtime/battery_detector.py` — o contexto no alerta.
* UI: `src/lib/api/io-carga.ts` (a régua), `io-carga-ao-vivo.ts` (o
  acompanhamento), `components/iot/CargaBadge.tsx` (o selo) e o modal de canal
  da Automação IoT (o cadastro da nominal e da sobreposição).
* Testes: `tests/test_carga_bateria.py` (85 casos com `tests/
  test_esquema_eletrico.py`) e `apps/nautica/tests/io-carga.test.ts` (26) — os
  pares (química, tensão) dos dois lados do limiar e da histerese estão lá, e
  servem de tabela-verdade para a implementação de vocês.

**Já no ar em dev** (`web-dev.marinetcs.com`, migração `087_carga_bateria`): o
banco AGM de partida da bancada já desce com
`"charge": {"on_v": 13.4, "off_v": 13.15, "sustain_s": 20.0}`, e o canal
"Alimentação iVS", sem química, desce com `"charge": null` — os dois casos que
o parse precisa cobrir.
