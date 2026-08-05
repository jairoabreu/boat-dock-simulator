# Handoff — o que falta na plataforma para Climatização e Bombas de porão

**Data:** 02/08/2026 · **Firmware:** `matel-ivs-display-p4` (branch `feature/nav-n2k-travessia`)
**Para:** plataforma web (`matel-web-platform-api`) · **Origem:** redesign 1.9_(6), telas 1 e 2
**Contraparte na tela:** `main/screen_clima.c`, `main/screen_bombas.c`

> **Resumo em uma linha:** as duas telas estão desenhadas e no ar; **Bombas**
> funciona com o que a plataforma já manda, **Climatização** não tem canal
> nenhum por baixo. Este documento lista os quatro campos que faltam — todos já
> **implementados no consumidor**, isto é, a tela passa a mostrar o dado no dia
> em que o `/hmi/config` começar a mandá-lo, sem novo firmware.

---

## 1. Situação por tela

| Tela | Estado | Depende de |
|---|---|---|
| **Bombas de porão** | **funcional** | nada — já usa `di_role: "bilge_pump"` + `flow_rate`/`flow_unit` |
| **Bombas — nível do porão** | oculto ("sem sensor") | `ai_role: "bilge_level"` (§2.1) |
| **Climatização — zona e ambiente** | **funcional** | `ai_role: "temperature"` numa Área (já existe) |
| **Climatização — umidade** | mostra `—` | `ai_role: "humidity"` (§2.2) |
| **Climatização — liga/desliga** | inerte | `do_role: "hvac_power"` (§2.3) |
| **Climatização — setpoint / modo / ventilador** | inerte | **não tem solução no modelo atual** (§3) |

---

## 2. Campos novos (contrato)

Todos entram em `channels[]` do `GET /api/v1/hmi/config`, no mesmo formato dos
papéis especiais já definidos no handoff de 02/08.

### 2.1 `ai_role: "bilge_level"` — nível do porão

Canal analógico cuja escala entrega **percentual** (`scale_min`/`scale_max` em
0–100), na Área onde a bomba está. A tela casa nível e bomba **pela Área**:
uma bomba sem AI de nível na mesma Área mostra "sem sensor" em vez de inventar.

```json
{ "kind": "ai", "node_id": 65, "channel": 3, "area_id": "casa-de-maquinas",
  "label": "Nível porão CM", "ai_role": "bilge_level",
  "volt_min": 0, "volt_max": 5, "scale_min": 0, "scale_max": 100, "unit": "%" }
```

Faixas de cor na tela (ordem decrescente): `>60% vermelho · >30% âmbar · resto teal`.

### 2.2 `ai_role: "humidity"` — umidade da zona

Idem, escala entregando **%RH**. A tela mostra no tile `UMIDADE` do card da zona.

### 2.3 `do_role: "hvac_power"` — relé de energia do ar

Saída digital que liga a unidade da zona. A tela liga o switch do card a esse
canal com o mesmo caminho das luzes (escrita **não-otimista**: o switch só
muda quando o `do_mask` do módulo confirmar).

```json
{ "kind": "do", "node_id": 66, "channel": 2, "area_id": "salao",
  "label": "Ar salão", "do_role": "hvac_power" }
```

> **Zonas são Áreas.** Não crie um cadastro paralelo de zonas: a tela monta uma
> zona para cada Área que tenha `hvac_power` **ou** sensor de temperatura. É o
> que o próprio design pede ("configuráveis por embarcação, não fixas em
> código").

---

## 3. ⚠ O buraco de verdade: setpoint, modo e ventilador

Isto **não se resolve com um campo novo no `/hmi/config`**, e é a decisão que
precisa ser tomada antes de a aba de climatização virar operação de verdade.

O iVS2008 fala DO (liga/desliga), DI (contato) e AI (tensão). Um setpoint de
22 °C, "modo frio" e "ventilador 2" são **valores**, não contatos — não há
por onde escoá-los. Três caminhos possíveis, em ordem de esforço:

1. **Só liga/desliga** (barato, hoje). O ar fica no termostato dele; a tela é
   apenas o disjuntor da zona. Some setpoint, modo e ventilador do desenho.
2. **Relés dedicados** (feio, mas existe). Modo e velocidade viram três ou
   quatro DOs por zona. Não resolve setpoint.
3. **Integração com o ar** (certo). Os equipamentos marítimos comuns (Webasto,
   Dometic, Marine Air) expõem RS-485/NMEA-2000 próprio. O caminho natural é o
   **CM06** falar com o ar e publicar no MTCP um comando de climatização — a
   tela já é cliente do CM06 e ganharia o controle inteiro.

Enquanto nenhum dos três existir, a aba mostra uma tarja âmbar dizendo que os
controles não acionam nada, e os ajustes vivem só na memória da tela. **Isso é
deliberado**: um card que parece operar o ar e não opera é pior que um card que
avisa.

---

## 4. Contadores de 24 h — quem deveria contar

A tela de bombas mostra **ciclos, tempo e volume em 24 h** e o gráfico por
hora. **Ninguém manda esses números**: a tela os conta sozinha, por borda de
subida do DI, e grava na NVS a cada virada de hora.

A limitação é estrutural: **o que a bomba fizer com a tela desligada não entra
na conta** — e bomba de porão trabalha justamente com o barco parado. O contador
deveria viver onde nunca falta energia:

- **melhor**: no próprio iVS2008 (contador por canal DI, lido por MTCP);
- **bom**: no CM06, que já tem o barramento e o 4G;
- **hoje**: na tela, com a ressalva acima.

Enquanto o relógio não sincroniza (sem SNTP), a tela troca o rótulo "Últimas
12 h" por "contando desde que a tela ligou", em vez de prometer uma janela que
não tem.

O limiar de alerta de infiltração está em **12 acionamentos em 24 h**, conforme
o design. Se a plataforma quiser esse limiar por embarcação, mande-o como
`ai_alarm.high` no canal da bomba e a tela passa a usá-lo.

---

## 5. Pendências anteriores ainda abertas

Repetindo do handoff de tipos especiais, porque continuam valendo:

1. **`pos_x`/`pos_y` sumiram** das três Áreas que ganharam `area_kind`. Sem
   posição, o marcador do cômodo cai no ângulo default do anel.
2. **Canais de tanque com `unit: "L"`** e escala 30–950 violam o §1.1 do
   contrato (em modo tanque a escala deve entregar **percentual**). A tela
   aceita as duas formas para não mostrar 566%, mas a origem continua errada.

---

## 6. Referência rápida do que a tela já faz

| Item | Origem | Observação |
|---|---|---|
| Lista de bombas | `di_role: "bilge_pump"` | máx. 4 na tela |
| Bombeando agora | `di_mask` do iVS2008 | tempo real |
| Volume 24 h | `flow_rate` × tempo contado | `gph`/`lph`/`lpm` normalizados |
| Nível do porão | `ai_role: "bilge_level"` | §2.1 — ainda não vem |
| Zona de A/C | Área com temperatura ou `hvac_power` | máx. 6 |
| Ambiente | `ai_role: "temperature"` da Área | já funciona |
| Umidade | `ai_role: "humidity"` | §2.2 — ainda não vem |
