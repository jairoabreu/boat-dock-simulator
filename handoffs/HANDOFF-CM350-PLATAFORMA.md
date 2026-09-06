# HANDOFF — CM350/CM350+ ↔ MaTel Web Platform (telemetria e reconfiguração)

Contrato definido no contexto do CM350 em 06/09/2026 (#335). A plataforma
implementa o **lado servidor** num serviço próprio, **porta 8350** (proposta),
HTTP simples no início; HTTPS quando houver certificado. A estação é sempre
quem inicia (funciona atrás de NAT/4G).

## Identidade e autenticação

- `X-CM350-Id: aa-bb-cc-dd-ee-ff` — MAC de fábrica do chip (minúsculas, hífen).
- `X-CM350-Key: <16 hex>` — token por dispositivo, derivado do MAC, mostrado
  na tela **Configurações → Wi-Fi e plataforma** ("Id … Token …"). A plataforma
  cadastra o par (id, token) na embarcação; requisição com token errado → 401.

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
- Futuro: campos N2K (leme, tanques) entram no mesmo objeto sem quebrar o resto.
- Resposta esperada: `204` ou `200` (corpo ignorado).

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
- `204` (ou `{}`) = nada a mudar. A estação aplica, salva em NVS e confirma
  **na telemetria seguinte** (os valores passam a refletir a config nova).
- **Segurança:** a estação **recusa** reconfiguração enquanto está **no
  comando** (posto 3) — a plataforma deve reenviar depois; nenhuma alteração
  é aplicada em silêncio durante a navegação.

## 3. Atualização de firmware

Continua pelo protocolo da CM01 (SoftAP oculto + `POST /update`); um OTA
puxado pela plataforma (URL de imagem no `/config`) fica para uma fase 2.

## Estado no CM350

Firmware 4.3" `9959100` (CM350+/firmware): `rede.c` (STA com até 4 redes,
cliente outbound, `/config`/`/estado` locais), tela Wi-Fi com busca e teclado.
2.8" recebe o mesmo na próxima gravação. Medição de impacto da telemetria no
ciclo MTNet (jitter) instrumentada e pendente de execução com a plataforma
(ou coletor local) no ar.
