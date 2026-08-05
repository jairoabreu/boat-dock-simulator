# Handoff — tipos especiais no `/hmi/config`

*(tanque, bomba de porão, guincho e tipo de cômodo)*

**Data:** 02/08/2026
**De:** plataforma web (`matel-web-platform-api` + `MaTel-web_platform`)
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)

> **Resumo em uma linha:** o `/hmi/config` passou a identificar os **tipos
> especiais** de tudo — tanque e temperatura (`ai_role`), bomba de porão
> (`di_role`), guincho (`do_role`) e o **tipo de cômodo** (`area_kind`) —
> cada um acompanhado dos campos que só fazem sentido nele.

> ⚠️ **Mudou desde a versão anterior deste handoff:** `tank_alarm` virou
> **`ai_alarm`**, e `low_pct`/`high_pct` viraram **`low`/`high`** na unidade
> do canal. Ver §1.3.

---

### ⛔ Correção: vocês estavam certos, o `/hmi/config` não estava mandando

Se vocês testaram e **nenhum** desses campos chegou, não foi erro de leitura
de vocês — era bug nosso, e já está corrigido no dev.

O endpoint declara `response_model=HmiConfigOut` e o **FastAPI filtra a saída
pelo schema**: campo que não está declarado no Pydantic é **descartado em
silêncio**. O serviço que monta a resposta (`hmi_config.py`) estava correto o
tempo todo; o schema (`schemas/hmi.py`) é que jogava fora na porta de saída.
Sem erro, sem log — só a tela recebendo menos do que a plataforma montou.

Iam para o lixo: `w`/`h` dos assets, `area_kind` das áreas e, nos canais,
`ai_role`, `ai_alarm`, `tank_kind`, `tank_capacity_l`, `dead_time_ms`,
`flow_rate`, `flow_unit` e `bilge_alarm`.

**Isso desmente o que eu afirmei antes** sobre a §3 do handoff de imagem —
eu disse que `w` e `h` já eram servidos. Não eram. Eu tinha validado o
`build_config` isolado, não a resposta HTTP. Agora está verificado pelo
endpoint de verdade, com o `response_model` ativo:

```
assets : [{'id': 'boat', 'w': 720, 'h': 405}, {'id': 'logo', 'w': 304, 'h': 108}]
áreas  : [('Camarote de bombordo','cabin'), ('Casa de máquinas','engine_room'),
          ('Praça de popa','cockpit')]
canais : ai_role=tank        ai_alarm={low:20, cooldown_min:30}   tank_kind=fuel
         ai_role=tank        ai_alarm={high:80, cooldown_min:30}  tank_kind=black_water
         ai_role=temperature ai_alarm={low:5, high:95, cooldown_min:15}
         di_role=bilge_pump  flow_rate=1100 flow_unit=gph  bilge_alarm={...}
```

Vale relerem tudo abaixo contra o que a tela recebe agora — o contrato
descrito aqui só passou a valer de fato com essa correção.

---

## 1. O contrato

Segue o mesmo padrão que a tela já trata para `di_role='bilge_pump'` e
`do_role='windlass'`: um papel especial no canal, com os campos que só fazem
sentido nele.

```json
{
  "node_id": 65, "kind": "ai", "channel": 0,
  "label": "Combustível BB",
  "unit": "%", "volt_min": 0, "volt_max": 10,
  "scale_min": 0, "scale_max": 100,

  "ai_role": "tank",
  "tank_kind": "fuel",
  "tank_capacity_l": 500.0,
  "ai_alarm": { "low": 20.0, "high": null,
                "cooldown_min": 30, "notify_company_users": true }
}
```

**`ai_role` ausente ou nulo = analógica genérica.** Nada muda para ela.

### 1.1 A regra que evita erro de conta

> **Em modo tanque, o valor escalado do canal JÁ É PERCENTUAL (0–100).**

A escala linear (`volt_min`/`volt_max` → `scale_min`/`scale_max`) faz a
conversão da tensão do sensor. A plataforma força `scale_min=0` e
`scale_max=100` ao marcar o canal como tanque.

A tela **não precisa saber nada da curva do sensor**: aplica a mesma conta
linear que já aplica hoje e o resultado é o percentual.

**Litros = `percentual / 100 × tank_capacity_l`.** Se `tank_capacity_l` for
nulo, mostrar só o percentual.

### 1.2 `tank_kind` — valores possíveis

| Valor | Fluido | Comportamento |
|---|---|---|
| `fuel` | Combustível | **esvazia** |
| `fresh_water` | Água doce | **esvazia** |
| `black_water` | Água negra | **enche** |
| `grey_water` | Água cinza | **enche** |
| `oil` | Óleo | **esvazia** |
| `other` | Outro | indefinido |

**Isto não é enfeite de ícone.** O tipo determina o **sentido** do alarme e,
provavelmente, a cor do indicador: um tanque de água negra a 90% é
**problema**, um de combustível a 90% é **ótimo**. Uma tela que pintasse
"cheio = verde" para todos estaria errada em metade dos casos.

### 1.3 `ai_alarm` — um formato para tanque E temperatura

```json
{ "low": 20.0, "high": null, "cooldown_min": 30,
  "notify_company_users": true }
```

> **Os limites vêm na UNIDADE ESCALADA do canal (`unit`), não em percentual
> fixo.** No tanque a unidade é `%`, então `low: 20` é 20%. Na temperatura é
> `°C`, então `high: 95` são 95 °C.

- **`low`** — alarme abaixo do piso. Combustível, água doce, óleo; e o frio
  num sensor de temperatura.
- **`high`** — alarme acima do teto. Água negra e cinza; e o superaquecimento.
- Opcionais e independentes; `null` = desligado. Temperatura costuma usar os
  dois.
- **`cooldown_min`** — intervalo entre avisos repetidos enquanto a condição
  persiste. Útil também para a tela, se ela alarmar localmente.
- `notify_company_users` é da notificação da plataforma; a tela pode ignorar.

### 1.4 `ai_role: "temperature"`

Não tem campos próprios além do `ai_alarm` — a escala do canal já entrega o
valor na unidade certa. A tela deve desenhar como leitura de temperatura
(termômetro/valor) e destacar ao cruzar qualquer um dos limites.

Para a tela, o útil é: **passou do limite → destaque visual**. Sugestão de
faixas, se quiser algo mais rico que ligado/desligado:

| Estado | Condição |
|---|---|
| normal | dentro dos limites |
| atenção | a 10 pontos percentuais do limite |
| alarme | passou do limite |

## 2. O que a tela precisa desenhar

Hoje uma `ai` provavelmente aparece como rótulo + valor + unidade. Para
tanque, o mínimo útil é:

- **Barra ou silhueta de nível** preenchida pelo percentual
- **Percentual** em destaque
- **Litros** quando houver capacidade — `320 L de 500 L`
- **Ícone/cor pelo tipo** de fluido
- **Destaque de alarme** ao ultrapassar o limite do sentido certo

O `label` continua sendo o nome que o operador deu ("Combustível BB"), e a
`area_id` continua posicionando o canal no mapa de bordo como qualquer outro.

## 3. Casos de borda que valem tratar

| Caso | O que fazer |
|---|---|
| `tank_capacity_l` nulo | mostrar só percentual, sem litros |
| `ai_role: "temperature"` | sem campos próprios — o valor sai da escala, na `unit` do canal |
| Percentual fora de 0–100 | fixar em 0/100 na barra, mas exibir o valor cru — sensor desregulado deve ser visível, não escondido |
| `tank_kind` = `other` | tratar como "esvazia" (o mais comum) e usar cor neutra |
| Os dois limites nulos | sem alarme, só indicador |
| `ai_role` desconhecido (futuro) | tratar como genérica, nunca falhar |

## 3.1 Os outros papéis especiais agora também vêm completos

Ao fazer o tanque, ficou visível que o contrato era desigual: a **bomba de
porão** chegava marcada e mais nada. Corrigido junto — a regra passa a valer
para todos:

> **Se o canal tem papel especial, os campos daquele papel vão juntos.**

| Papel | Campo | Campos que acompanham |
|---|---|---|
| Tanque | `ai_role: "tank"` | `ai_alarm`, `tank_kind`, `tank_capacity_l` |
| Temperatura | `ai_role: "temperature"` | `ai_alarm` |
| Bomba de porão | `di_role: "bilge_pump"` | `flow_rate`, `flow_unit`, `bilge_alarm` |
| Guincho | `do_role: "windlass"` | `pair_channel`, `dead_time_ms` |

A vazão da bomba é o que transforma *"ligada há 4 minutos"* em *"bombeou
80 litros"* — havia 5 bombas com vazão cadastrada e nenhuma chegava completa
à tela. `flow_unit` é `gph`, `lph` ou `lpm`.

## 3.2 Cômodos agora têm tipo — `area_kind`

Cada área do `/hmi/config` passa a trazer `area_kind`, ao lado do `name`:

```json
{ "id": "96166ac3-…", "name": "Camarote de bombordo",
  "area_kind": "cabin", "icon": "ship", "accent": null,
  "pos_x": 63.0, "pos_y": 66.7, "label_pos": null }
```

> **O `name` manda na EXIBIÇÃO. O `area_kind` governa ÍCONE, COR e
> AGRUPAMENTO.**

Sem ele a tela teria de interpretar o texto — e o mesmo cômodo aparece
cadastrado como "Casa de máquinas" e "Motor", camarote como "Camarote BB",
"Camarote de bombordo" e "Suíte de proa". Adivinhar por texto quebra no
primeiro barco que escrever diferente.

| Valor | Cômodo |
|---|---|
| `engine_room` | Casa de máquinas |
| `cabin` | Camarote / suíte |
| `salon` | Salão |
| `galley` | Cozinha |
| `head` | Banheiro |
| `cockpit` | Praça de popa |
| `flybridge` | Flybridge |
| `helm` | Posto de comando |
| `bow` | Proa |
| `bilge` | Porão |
| `deck` | Convés |
| `storage` | Paiol |
| `utility` | Serviço |
| `other` | Outro |

O vocabulário saiu dos nomes **reais** já cadastrados, não de um catálogo
inventado.

**`area_kind` nulo é o estado das áreas antigas** — tratar como `other` e
seguir. E, como sempre: valor desconhecido no futuro deve cair em genérico,
nunca falhar.

Os **assets** continuam se distinguindo só por `id` (`boat` / `logo`).

## 4. O que NÃO mudou

- O `/hmi/config` continua com a mesma forma; os campos são **aditivos**.
- `unit`, `volt_min/max`, `scale_min/max` seguem existindo e com o mesmo
  significado — em modo tanque só passam a ter valores fixos por convenção.
- Canais analógicos genéricos não têm `ai_role` e seguem exatamente como
  antes. Firmware que ignorar os campos novos continua funcionando.

## 5. Como testar

Já existem dois tanques configurados na bancada
(`NX 50 Invictus - Demonstração`, iVS2008 `2606200005`, nó `0x41`):

| Canal | Tipo | Capacidade | Alarme |
|---|---|---|---|
| `ai` 0 | `fuel` | 500 L | mínimo em 20% |
| `ai` 1 | `black_water` | 120 L | máximo em 80% |
| `ai` 3 | `temperature` | −10 a 120 °C | 5 °C / 95 °C, a cada 15 min |

E três áreas já tipadas na mesma embarcação:

| Área | `area_kind` |
|---|---|
| Casa de máquinas | `engine_room` |
| Camarote de bombordo | `cabin` |
| Praça de popa | `cockpit` |

Tudo já sai no `/hmi/config` — basta um poll.

## 6. Pendente do lado da plataforma

O **motor de notificação** do alarme de tanque ainda não existe (o da bomba
de porão está em `matel/realtime/bilge_detector.py` e serve de molde). Hoje
`tank_alarm` é entregue à tela, mas a plataforma ainda não dispara aviso por
push/e-mail. Se a tela quiser alarmar localmente, pode — e é até melhor,
porque não depende de conectividade.
