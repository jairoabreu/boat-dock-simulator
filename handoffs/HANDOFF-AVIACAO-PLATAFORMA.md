# HANDOFF — MaTel Aviation ↔ plataforma de voo (flight.marinetcs.com)

Contrato da FASE 0, escrito no contexto do app de aviação em 13/10/2026.
Plataforma = o MESMO código da plataforma náutica (`~/matel-web-platform-api`,
`~/MaTel-web_platform-main`) com a aviação como nova vertical, como foi feito
com geradores — mas numa **instância própria** (infra separada dos barcos).
A implementação da API e da web acontece numa sessão aberta nos repos da
plataforma; o lado do iPad, em `matel-aviation-app`.

## Decisões do dono (13/10)

1. O **diário de bordo vai para a nuvem** (inclui código ANAC dos tripulantes) → LGPD: consentimento, quem vê, exclusão.
2. **Rastreamento ao vivo** durante o voo (4G do iPad), além do envio do voo gravado.
3. Clientes: **todo mundo** — proprietários, escolas, operadores, oficinas → multiempresa, vários pilotos por aeronave, um piloto em várias aeronaves/empresas.
4. Domínio: **flight.marinetcs.com** (web) e **flight.marinetcs.com/api/v1** (API, mesma origem → sem CORS).
5. Infra: os droplets DigitalOcean do app **PDA** (sem uso). `pda.marinetcs.com` → 24.144.107.128 ainda responde (uvicorn atrás de Caddy) e a porta 22 está fechada para o Mac. **Nada no PDA é apagado antes do dono dizer o que guardar.**

## Infra (instância "flight")

- Mesma pilha dos barcos em compose: `flight-api` (imagem da API), `flight-web` (`apps/aviacao`), Postgres+Timescale, Redis, RabbitMQ, Traefik (ou o Caddy que já está lá). **Sem o gateway Go** (não há rastreador TCP; tudo chega por HTTPS).
- Banco próprio: contas da aviação não se misturam com as dos barcos (quem tem barco e avião tem duas contas — aceitável agora).
- Migrações: as mesmas do repo da API (as da aviação são aditivas; no servidor dos barcos ficam inertes).
- Backups: `pg_dump -Fc` diário + snapshot do droplet. **Compressão Timescale ligada** nas hypertables de voo (diferente dos barcos, que guardam tudo sem compressão).

## Modelo de dados (novo)

Genérico por `entity_kind/entity_id`; nada de copiar o padrão `vessel_id`.

- `companies.primary_kind` ganha `'aviation'`; `devices.entity_kind` / `coordinates.entity_kind` ganham `'aircraft'`; `devices.protocol` ganha `'efb'`; `hw_kind` ganha `'uuid'`.
- **`aircraft`**: id, company_id, `registration` (PR-III), modelo, fabricante, número de série, motor (modelo, nº de série, TBO h), hélice, `engine_cyl` (4/6), limites do motor (EGT/CHT/óleo/RPM, alimentam alertas), foto, `last_*` denormalizados (posição/estado ao vivo), created/updated.
- **`pilot_profiles`** (1:1 com `users`): nome completo, **código ANAC (6 dígitos)**, licenças/habilitações + validades, CMA (validade), telefone; consentimento LGPD (data/versão do termo).
- **`aircraft_crew_access`**: user ↔ aircraft (papel: piloto, instrutor, mecânico, observador). Generalizar o ACL hoje restrito a embarcação (`user_vessel_access`) em `user_entity_access(entity_kind, entity_id)`.
- **`flights`** (1 por voo gravado): `id` = **UUID gerado no iPad** (idempotência), aircraft_id, device_id, pilot_user_id, `engine_start/takeoff/landing/engine_stop` (UTC), `from_icao/to_icao` (+ pernas/toques), `flight_h`, `night_h` (sol < −6°, RBAC 01), `block_h`, distância, `fuel_used_gal`, máx. alt/GS, status (`recording` | `complete`), `source` (`efb` | `flightmate`), resumo do motor (máx EGT/CHT etc.).
- **Trajeto**: reaproveita `coordinates` (hypertable existente) com `entity_kind='aircraft'`, `altitude_m`, `speed_kt`, `course`; VS e fonte do GPS em `raw` — assim o histórico/replay do mapa (`/positions/track?device_id`) já funciona. + coluna/índice `flight_id` (nullable) para recortar por voo.
- **`aircraft_engine_samples`** (hypertable NOVA — a `engine_telemetry` é de barco: instance=BB/BE, sem cilindros): time, aircraft_id, flight_id, rpm, map_inhg, ff_gph, fuel_used_gal, `egt_f[]` e `cht_f[]` (arrays por cilindro), oil_t_f, oil_p_psi, tit_f, volts, amps, oat_c, carb_t, `raw` jsonb. NULL = desconhecido (nunca zero).
- **`logbook_entries`** (Res. ANAC 457, art. 4º): id (UUID do iPad), aircraft_id, **`number` sequencial POR AERONAVE atribuído pelo servidor**, flight_id (opcional), data, de/para, horários (partida, decolagem, pouso, corte), horas de voo/noturnas/IFR, pousos, natureza do voo, pessoas a bordo, carga, combustível, ocorrências, tripulação (`[{user_id?, anac_code, função P/I/O/C/M}]`), `confirmed_by` + `confirmed_at`, `signature` (hash), status (`draft` | `confirmed` | `corrected`). Confirmada não se edita: correção = nova versão ligada (`corrects_id`), como em papel.
- **`flight_plans`** (fase 4): o plano do PLANO/FPL do app (pontos, cruzeiro, razões, ETE/combustível) por aeronave.

## Identidade e autenticação

- **Usuário**: login normal da plataforma (`POST /auth/login`, JWT) dentro do app.
- **Pareamento do iPad** (uma vez por aeronave): `POST /aviation/devices/pair` (JWT) `{aircraft_id, device_uid, name:"iPad Air 5", app_version}` → cria/reusa `devices` (`protocol=efb`, `hw_kind=uuid`) e devolve **token de device `mtd_…`** (o padrão que já existe: `current_device`). O iPad guarda o token no Keychain; todo envio de dados usa `Authorization: Bearer mtd_…`.
- FlightMate (caixa): não fala com a plataforma direto; os dados dela chegam pelo iPad, com `source=flightmate` + número de série da caixa no voo.

## API — envio de dados (iPad → plataforma)

Tudo idempotente, offline-first: o iPad grava local, enfileira e reenvia até receber 2xx. `Content-Encoding: gzip` aceito em todos.

### 1. Ao vivo — `POST /aviation/live`
A cada **5 s** em voo (com 4G), os pontos desde o último envio confirmado:
```json
{"flight_id":"…uuid…","pts":[[1760360400,-27.6704,-48.5525,1676,172,359,-640], …],
 "eng":[{"t":1760360400,"rpm":2500,"map":24.1,"ff":16.2,"egt":[1380,1395,…],"cht":[350,…],"oil_t":190,"oil_p":62}]}
```
`pts` = `[t_epoch_s, lat, lon, alt_ft, gs_kt, trk_deg, vs_fpm]` (o mesmo `TrackPt` do app). Resposta `200 {"ack_t": <último t gravado>}`. A plataforma grava em `coordinates`/`aircraft_engine_samples`, atualiza `aircraft.last_*`, publica no Redis (mapa ao vivo) **e no RabbitMQ `matel.positions`** (`kind=position`, `entity_kind=aircraft`) — senão os detectores (cercas/automações/alertas) não veem o avião (hoje a ingestão HTTP do CM350 pula o RabbitMQ). Sem rede: o iPad acumula e manda tudo depois (com `atrasada`), sem perder pontos.

### 2. Voo gravado — `PUT /aviation/flights/{flight_id}`
Ao terminar o voo (ou quando voltar a ter internet): o cabeçalho + o trajeto completo + o motor (colunar, gzip — 4 h a 1 Hz ≈ 150 kB). **PUT repetido substitui** (sem duplicar): apaga os pontos do voo e regrava na mesma transação. Completa o que o ao-vivo não pegou (buracos de 4G). Resposta `200` com o voo.

### 3. Diário de bordo — `PUT /aviation/logbook/{entry_id}`
Quando o piloto confirma ("converter em voo realizado"). O servidor atribui o **número sequencial da aeronave** (vários iPads/pilotos na mesma aeronave não podem colidir) e devolve: o app troca o número provisório pelo definitivo. Confirmada → imutável; correção = nova entrada com `corrects_id`.

### 4. Leitura para o app
`GET /aviation/aircraft` (as que o usuário acessa), `GET /aviation/aircraft/{id}/logbook?cursor=` (sincroniza o diário entre iPads), `GET /aviation/flights?aircraft_id=&cursor=`.

## Web — `apps/aviacao` (flight.marinetcs.com)

Copiar e enxugar a `apps/nautica` (padrão do repo), **extraindo antes** `packages/ui` (já idêntico nos dois apps) e `packages/map-playback` (mapa + replay) — terceira cópia triplicaria a dívida.
Telas: login/empresas/usuários/papéis (cópia), **frota** (aeronaves + estado ao vivo), **mapa ao vivo**, **voos** (lista → replay no mapa com perfil de altitude + gráficos do motor sincronizados), **diário de bordo** por aeronave (exportação PDF no formato ANAC), **pilotos** (perfil, validades de CMA/habilitação com aviso), **manutenção** por horas (TBO, 50/100 h, anual — reaproveita `maintenance`), documentos da aeronave. Unidades de aviação (ft, kt, ft/min, °F/°C configurável), horários em UTC (Z).

## Permissões (catálogo novo)
`aircraft:read|write`, `flights:read`, `logbook:read|write|confirm`, `pilots:read|write`, `maintenance:*` (existente). Piloto sempre vê as próprias entradas do diário em qualquer empresa; o resto segue a árvore de empresas + o ACL por aeronave.

## LGPD
Termo de consentimento no pareamento/primeiro login (versão + data em `pilot_profiles`); código ANAC e dados pessoais visíveis só a quem tem `pilots:read` na empresa e ao próprio piloto; exportação e exclusão a pedido (diário confirmado é registro legal da aeronave → anonimiza o tripulante em vez de apagar a entrada).

## Fases
- **0** este contrato ✔ (falta: acesso ao PDA e o que guardar dele).
- **1** API (repo da plataforma, deploy só na instância flight de DEV primeiro): modelo + pareamento + `/live` + `PUT flights` + `PUT logbook` + publicação no RabbitMQ.
- **2** App: login/pareamento, fila offline, motor por ponto no voo gravado, envio ao vivo, sincronização do diário.
- **3** Web `apps/aviacao` + pacotes compartilhados.
- **4** Alertas de motor (limites da aeronave), manutenção por horas, planos de voo, áreas/espaços aéreos, FlightMate.

## Pendências para começar
- [ ] Dono: liberar SSH no(s) droplet(s) do PDA (firewall da DigitalOcean na porta 22, ou a porta certa) e dizer se há algo do PDA a guardar (banco/arquivos) antes de reaproveitar.
- [ ] DNS: `flight.marinetcs.com` → droplet (A record) quando a instância subir.
- [ ] Dono: termo LGPD (texto) — posso rascunhar.
