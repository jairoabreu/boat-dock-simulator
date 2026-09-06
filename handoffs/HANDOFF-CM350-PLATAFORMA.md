# HANDOFF — CM350/CM350+ ↔ MaTel Web Platform (telemetria e reconfiguração)

Contrato definido no contexto do CM350 em 06/09/2026 (#335) e IMPLEMENTADO
na plataforma no mesmo dia (cartões #342–#345 do quadro 29): serviço no
mesmo processo da API (`matel/routers/cm350.py`), **porta 8350 em HTTP
puro**, publicada direto do container — a estação não fala TLS e o Traefik
da porta 80 redireciona para HTTPS. A estação é sempre quem inicia (funciona
atrás de NAT/4G).

**Base em dev:** `http://api-dev.marinetcs.com:8350/api/v1/cm350` (é o que a
estação precisa ter em `url`; a plataforma mostra o valor em
GET /devices/{id}/cm350 e na seção da estação do formulário de dispositivo).

**Cadastro na plataforma:** Dispositivos → Novo → tipo "Estação CM350 (tela
2,8")" (`model=cm350`) ou "Estação CM350+ (tela 4,3")" (`model=cm350p`), MAC
com 12 hex (o mesmo formato do CM06/tela: `80F1B2D37A6E`), protocolo `cm350`
automático, vínculo com a embarcação. Não há token a emitir: ele é derivado.

## Identidade e autenticação

- `X-CM350-Id: aa-bb-cc-dd-ee-ff` — MAC de fábrica do chip (minúsculas, hífen).
- `X-CM350-Key: <16 hex>` — token por dispositivo, DERIVADO do MAC de fábrica
  com a mesma conta nos dois lados (`rede_token()` em rede.c e
  `token_do_mac()` em matel/services/cm350.py), em aritmética de 32 bits:

      a = (m0<<24 | m1<<16 | m2<<8 | m3) * 2654435761
      b = ((m2<<24 | m3<<16 | m4<<8 | m5) * 2246822519) ^ 0x0C350
      token = "%08x%08x" % (a, b)      # ex.: 80:f1:b2:d3:7a:6e → 09f75ee387e27672

  A estação mostra o valor em **Configurações → Wi-Fi e plataforma** ("Id …
  Token …"); a plataforma recalcula e compara em tempo constante. Qualquer
  falha (MAC não cadastrado, modelo não-CM350, device inativo, token
  diferente) → **401 uniforme**, sem revelar o inventário.

## 1. Telemetria — `POST <base>/telemetria`

Corpo JSON (é o mesmo `GET /estado` local da estação), a cada
`telemetria_s` segundos (Desligada/1/5/10/30 na tela; 0 = desligada):

```json
{"id":"80-f1-b2-d3-7a-6e","fw":"0.1.0","posto":3,"master":"0x00","evento":"0x0000",
 "bb":{"on":1,"rpm":1450,"marcha":"F","thr":42,"falha":0},
 "be":{"on":1,"rpm":1440,"marcha":"F","thr":42,"falha":0},
 "trafego":1,"tx_perdidos":0,"bus_offs":0,
 "jitter_max_ms":2,"jitter_med_x10":2,"nav_max_ms":21,"telemetrias":1234}
```

- `posto`: 0 sem comando, 1 outra estação no comando, 2 chamando, 3 no comando.
- `master`: endereço MTNet da estação no comando (0x21 CM01, 0x22–0x24 CM350).
- `evento`: código da EventTable da CM01 (0x1010 ECU sem resposta, 0x1020
  colisão de ID, 0x1030 distúrbio, 0x15xx atuadores) ou 0x0000.
- `marcha`: F/N/R; `thr` 0–100 %; `falha`: byte Fail do ECUStatus (planilha MTCP).
- **`cfg`** (firmware ≥ 06/09): a config que a estação REPORTA —
  `{"rpm_max":2500,"rpm_engate":700,"instancia":2,"brilho":100,"idioma":0,
  "som":1,"som_toque":0,"som_neutro":0,"telemetria_s":1,"url":"…",
  "wifi_ssid":"…"}` (nunca a senha). É como a plataforma confirma a
  reconfiguração: `GET /config` devolve só o que difere disto.
- Futuro: campos N2K (leme, tanques) entram no mesmo objeto sem quebrar o resto.
- Resposta esperada: `204` (corpo ignorado). A plataforma grava a linha viva
  em `cm350_status`, uma amostra por motor ONLINE em `engine_telemetry`
  (`dialect='mtnet'`, instance 0 = BB / 1 = BE: rpm, marcha→trans_gear,
  manete→throttle_pct, falha em raw), carimba `devices.last_seen_at` e
  publica `kind: cm350_status` no canal da empresa (WS).

## 2. Reconfiguração — `GET <base>/config?id=<id>`

Logo após cada telemetria a estação pede a config desejada. Resposta `200`
com JSON contendo **só os campos a alterar** (qualquer subconjunto):

```json
{"rpm_max":3000,"rpm_engate":700,"instancia":2,"brilho":80,"idioma":0,
 "som":1,"som_toque":0,"som_neutro":1,"telemetria_s":5,
 "url":"http://matel.ind.br:8350/cm350","wifi_ssid":"...","wifi_senha":"..."}
```

- Faixas: rpm_max 500–10000; rpm_engate 0–3000 (0 = sem limite); instancia
  1–4 (→ endereço 0x21–0x24, aplicado ao vivo); brilho 5–100; idioma 0 PT /
  1 EN; som* 0/1; telemetria_s 0–3600.
- `{}` = nada a mudar. A plataforma devolve **só os campos da config DESEJADA
  (PUT /devices/{id}/cm350/config, pelo operador) que diferem da `cfg`
  reportada**; a estação aplica, salva em NVS e confirma na telemetria
  seguinte, quando `cm350_config.applied_at` é carimbado. `wifi_senha` só
  acompanha quando o `wifi_ssid` desejado difere do reportado. Sem `cfg`
  (firmware antigo) a desejada vai inteira, idempotente.
- **Segurança:** a estação **recusa** reconfiguração enquanto está **no
  comando** (posto 3) — a plataforma deve reenviar depois; nenhuma alteração
  é aplicada em silêncio durante a navegação.

## 3. Atualização de firmware

Continua pelo protocolo da CM01 (SoftAP oculto + `POST /update`); um OTA
puxado pela plataforma (URL de imagem no `/config`) fica para uma fase 2.

## Estado (06/09/2026)

- Plataforma: API `722eaad` (matel-web-platform-api: protocolo `cm350`,
  migração 105 com `cm350_status`/`cm350_config`, rotas da estação e do
  operador), web `d785ce7` (MaTel-web_platform: cadastro dos dois modelos,
  seção Id/Token/URL + reconfiguração remota, card do mapa).
- Firmware: 4.3" e 2.8" mandam `cfg` na telemetria (rede.c). **URL de
  fábrica** = base dev acima (dono, 06/09: "pode gravar essa por enquanto");
  NVS vazia → fábrica. Com a telemetria DESLIGADA a estação ainda consulta
  `GET /config` a cada 60 s — dá para reconfigurar desde o 1º boot. A tela
  Wi-Fi mostra servidor atual, hora do último envio (NTP, fuso de Brasília),
  OK/FALHA e contagem. **Estação real 4.3" (80F1B2D37A6E) enviando ao dev
  desde 06/09 12:33 UTC** (período 1 s escolhido na tela).
- Medição do impacto da telemetria no ciclo MTNet: instrumentada
  (`jitter_*`), roteiro em CM350+/tools/medicao, pendente de rede comum.
