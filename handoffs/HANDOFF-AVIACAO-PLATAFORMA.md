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
5. Infra: o droplet do PDA foi apagado pelo dono (13/10) e no lugar dele nasceu o **flight-1 = 165.227.78.93** (DigitalOcean NYC3, Premium AMD 2 vCPU / 4 GB / 80 GB NVMe, Ubuntu 24.04). Preparado em 13/10: Docker + compose, usuário `deploy` (sudo, grupo docker), SSH só por chave, ufw 22/80/443 (+ firewall da DO), fail2ban, swap 2 GB, atualizações de segurança automáticas, pasta da pilha `/srv/flight`.

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
- **0** este contrato ✔ + servidor flight-1 preparado ✔.
- **1** API ✔ (14/10) — branch `feat/aviacao` do `~/matel-web-platform-api` (worktree `~/matel-api-aviacao`), migração **115_aviacao**, no ar em `https://flight.marinetcs.com/api/v1` (instância flight-1: compose em `/srv/flight`, banco próprio, backup diário 04:17 UTC, 14 dias). E2E `scripts/e2e_aviacao.py` passou inteiro (login → aeronave → pareamento → ao vivo sem duplicar → voo completo idempotente → diário nº 1 + correção nº 2 → tráfego FR24 → 401 com token ruim).
  - Login: `POST /api/v1/auth/login` com **JSON** `{"email","password"}` → `access_token`/`refresh_token`; `GET /auth/me` traz a empresa.
  - Flightradar24 (pedido do dono 14/10): `GET /aviation/traffic?bounds=N,S,W,E` (JWT **ou** token do iPad) e `GET /aviation/aircraft/{id}/fr24` (posição pela matrícula, p/ quem voa sem o app). Chave só no `.env` do servidor; cache de 15 s no Redis; **nada da FR24 vai para o banco** (regra deles: máx. 30 dias). Hoje com a chave de SANDBOX (dados fixos de teste).
  - ⚠ Migração 115 nasceu no branch da aviação: se o branch dos barcos ganhar outra 115 antes do merge, renumerar (alembic com duas cabeças).
- **2** App: login/pareamento, fila offline, motor por ponto no voo gravado, envio ao vivo, sincronização do diário.
- **3** Web `apps/aviacao` + pacotes compartilhados.
- **4** Alertas de motor (limites da aeronave), manutenção por horas, planos de voo, áreas/espaços aéreos, FlightMate.

## Pendências para começar
- [x] Servidor flight-1 (165.227.78.93) criado e preparado.
- [x] DNS: `flight.marinetcs.com` → 165.227.78.93 (A, somente DNS na Cloudflare) + HTTPS Let's Encrypt OK; página provisória (Caddy em /srv/flight/placeholder — remover quando a pilha subir).
- [ ] Dono: termo LGPD (texto) — posso rascunhar.

### 19/10/2026 — perfil / filtros web

Trabalho no checkout de aviação `/Users/jairo/MaTel-web-aviacao` (`feat/aviacao-web`), e não em `MaTel-web_platform-main` (nautica/geradores). Web: botão Limpar pontos preserva plano/configurações, pede confirmação e salva pelo fluxo existente; pílulas padrão (preferência anterior de lista respeitada); perfil com área de desenho fixa e legenda fora; estrelas nas entradas de conflito com terreno e preenchimento vermelho só acima da rota, sem atravessar falhas de dados. Vento no perfil é componente longitudinal arredondada (proa/esquerda, cauda/direita, zero sem seta); mapa preserva vetor completo.

Menu Pontos DECEA nos mapas FPL e MAP: AD, HP, VFR, FIXO IFR, auxílios VOR/NDB/DME; preferências independentes por superfície, menu permanece aberto ao marcar, fecha ao clicar fora; grupos desligados não entram no snapping da rota. 32 testes Node passam, build produção passa e eslint dos arquivos alterados sem avisos. Teste Chromium com API fictícia valida filtros, persistência, clique fora, colisões e limpar/cancelar/salvar, sem erros de página. Lint global mantém 3 erros preexistentes de fast-refresh nos wrappers UI.

Publicação concluída e verificada por igualdade byte a byte do HTML, JS e CSS públicos em `https://flight.marinetcs.com/`: arquivos estáticos em `/srv/flight/web`, SSH alias `flight-1` (chave definida no config), Caddy serve direto. Copiar assets antes de index e preservar assets anteriores; backup `/srv/flight/backups/web-20261019-profile-filters-before`. Não alterar pilhas náuticas.

### 19/10/2026 — PACK manual e altitudes web / build 43

Web FPL agora só busca meteorologia da rota/modelo, relevo do perfil e espaços aéreos do perfil ao pressionar PACK. Removidos disparos por abrir editor/picker, mover mapa, editar altitude e temporizadores. Estações METAR do FPL usam o pacote (MAP mantém camada ao vivo). Recibo por assinatura dos parâmetros de voo, com validade de 30 minutos e indicador vermelho quando ausente/alterado/expirado; falha de armazenamento não registra sucesso. Guarda até quatro rotas por usuário/empresa em localStorage. Service worker cacheia o shell público exclusivamente pelo PACK; offline restaura usuário, frota, lista/detalhe dos planos baixados, WX, perfil e declinação. Mapa-base, cartas e camadas ao vivo não são incluídos neste pacote. Preferências de pontos DECEA preservadas.

No web e iPad, removidas sugestões inline de vento/altitude. ALTITUDES no canto superior direito do mapa abre tabela vertical, níveis altos acima, sugestão de menor ETE verde e atual magenta. iPad estreito mantém acesso no editor. Web testado no Chromium: zero downloads WX/relevo antes de PACK, persistência após reload, reload sem rede e acesso via lista offline, mudança de altitude invalida recibo, posição direita. 35 testes Node passam, build e eslint dos arquivos alterados passam. Service worker testado com Vary: Origin (arquivos públicos same-origin com ignoreVary no fallback).

Publicado em flight.marinetcs.com; HTML, JS, CSS e pack-sw.js públicos conferidos byte a byte. Backup antes da publicação: /srv/flight/backups/web-20261019-pack-altitudes-before. Fontes em /Users/jairo/MaTel-web-aviacao; nenhuma mudança nas pilhas náuticas/API.

### 19/10/2026 — imagens e cartas no PACK web

- Escopo: `MaTel-web-aviacao/apps/aviacao` + API de aviação; nenhum build iPad nesta etapa.
- PACK manual inclui extrato OSM da faixa da rota (10 NM de cada lado), imagens WAC/REA/ARC até z11, ENRC L/H até z10 e PDFs oficiais dos aeródromos presentes no FPL. Sobrezoom usa as imagens salvas. Satélite Esri permanece online.
- OSM é renderizado como mapa vetorial simplificado (vias/cidades/hidrografia/pistas), com seleção de detalhes conforme zoom/área visível. A escolha `OSM offline` permite conferência ainda online; a desconexão ativa essa base automaticamente. Aviso ao sair da área salva. A lista `Cartas salvas` abre PDFs do CacheStorage sem rede e mostra a data da base OSM.
- Não há download em lote das imagens públicas OSM. Base própria do Brasil derivada do extrato Geofabrik de 18/10/2026, com atribuição ODbL. Importação manual documentada em `matel-api-aviacao/docs/AVIATION-OSM-PACK.md`; nenhum agendamento criado.
- API: `/aviation/charts/plates/catalog/{icao}`, `/plates/pdf/{icao}/{ident}` (URLs e redirecionamentos restritos a AISWEB); `/aviation/charts/osm/corridor` (consulta limitada, SQLite RTree próprio). Não usa Overpass em produção. O serviço público retornou 406/timeouts nos testes; foi substituído pela base local.
- Preparação usa cache temporário por PACK, progresso/cancelamento, validação PNG/PDF/JSON, limite de espaço e verificação de arquivos ao reabrir. Falha não substitui recibo anterior. Guardam-se até quatro rotas por usuário/empresa; caches antigos são removidos após gravar o novo recibo.
- Pontos DECEA e espaços da rota ficam no snapshot para uso offline. PACKs antigos, sem imagens, continuam com aviso de atualização. A navegação offline do FPL e a lista de PDFs foram verificadas no Chrome com rede desativada. O mapa da frota ao vivo não seleciona automaticamente um PACK.
- Backup web: `/srv/flight/backups/web-20261019-pack-assets-before`. Backup API: `/srv/flight/backups/api-20261019-pack-assets/aviation_charts.py`; imagem anterior `flight-api:before-pack-assets`. A API foi publicada apenas no ambiente `flight`.
- Verificação até esta anotação: 37 testes web, quatro testes unitários Python; testes de navegador para PACK manual, reinício offline, PDF renderizado, cartas em cache, cancelamento, arquivo inválido e cache removido; catálogo/PDF SBST e cinco camadas DECEA reais confirmados. Publicação web e teste final OSM registrados no complemento abaixo após a importação.

#### Conclusão da importação e publicação — 19/10/2026

Base OSM concluída com 6.093.547 elementos; timestamp `2026-10-18T20:25:06Z`; SQLite de 2.107.219.968 bytes em `/app/uploads/osm-brazil/map.sqlite` no volume `flight_uploads`. Integridade verificada antes da troca atômica. Fonte PBF preservada em `/srv/flight/osm-import/brazil.osm.pbf`, MD5 `00e6a17e8e33ffd13ae3e1c30c6ab424`. Container temporário de importação removido após saída 0. Usar importação nativa documentada em futuras atualizações; não repetir as tentativas lentas com BackReferenceWriter.

Consulta real SBFL–SDIM: HTTP 200, 32.578 elementos, 14.607.691 bytes, 6,61 s. Teste Chromium com assets reais SBFL–SSKT: 119 arquivos / 36.041.108 bytes, 24 PDFs; PACK manual, recarga com rede desligada, mapa OSM com cidades, ADC SBFL renderizada e WAC em cache, sem erros JavaScript. Autenticação, meteorologia e relevo desse teste usam fixtures; OSM e cartas vêm da API pública real. Corrigida ordem visual: OSM vetorial e suas legendas ficam em pane 190, abaixo das cartas raster.

Nova web publicada em `https://flight.marinetcs.com`. HTML, worker e arquivos JS/CSS públicos conferidos byte a byte com dist. Entrada `index-CmOIDgdA.js` e `index-nlbix9Vg.css`; API health OK. Worker aguarda atualização/ativação e exige protocolo v2 antes de confirmar o PACK; teste de migração de worker antigo passou. Os PACKs anteriores devem ser refeitos pelo botão para ganhar mapa e cartas. Nenhum build iPad criado nesta etapa.

Verificação final também executada contra o domínio público após publicar: PACK real concluído, recarga offline, OSM, PDF ADC e WAC renderizados, ordem das camadas correta, nenhum erro de página. Evidência: `/tmp/pack-public-browser.log` e `/tmp/web-pack-public-{osm,pdf,chart}-offline.png`.


### 19/10/2026 — PACK iPad e prévia 3D web / build 44

O PACK explícito do iPad agora inclui o mesmo extrato OSM próprio (±10 NM), cinco camadas DECEA com sobrezoom e PDFs dos aeródromos do FPL. `PackAssetsStore` valida os bytes, prepara arquivos temporários, restaura o cache anterior se a instalação falhar/cancelar, publica manifesto atômico e verifica integridade ao reiniciar. Mantém quatro manifestos; mapas próprios antigos são removidos, cartas/PDFs compartilhados permanecem acessíveis no cache NAV. Nenhuma chamada em lote a tile.openstreetmap.org. Os recibos antigos foram invalidados (V2): pressionar PACK novamente para incluir os novos assets.

Mapa nativo ChartMap desenha OSM offline por baixo das cartas, com atribuição e aviso fora da cobertura. Camada OSM pode ser desligada no menu. O FPL mostra Cartas salvas com data da base, lista PDFs sem buscar catálogo e abre o visualizador nativo existente. Sobreposição selecionada persiste pelo ActivePlateStore e aparece em FPL/NAV, com opacidade/remoção. Relevo mantém faixa de planeio de 30 NM; meteorologia só atualiza pelo PACK. Imagens de satélite/3D não estão incluídas.

Validação iPad: suite completa 398 testes passou; teste adicional do painel salvo passou em tablet e telefone. Após ajuste do ciclo de imagens do mapa, 40 testes de mapa/FPL/painel/render OSM passaram. Análise direcionada limpa. Teste de produção SBFL–SSKT baixou 94 rasters, 24 PDFs, 20.693 elementos OSM, 36.050.594 bytes e validou recarga com transporte de rede proibido. Live test é opt-in (`PACK_LIVE=1`). Não foi instalada versão USB.

Web: botão 3D abre prévia do perfil planejado com reprodução/pausa, reinício, velocidade 1–100×, linha do tempo, câmeras externa/cabine e volumes ilustrativos das nuvens salvas no PACK. Sem download WX ao abrir/reproduzir. Velocidade planejada sem vento; cenário AWS/Esri requer internet. Segue os endpoints do perfil atual, sem extensão de rolagem de pista. Reutiliza Replay3D sem alterar seu replay de telemetria.

Web validada: 40 testes Node, build produção, ESLint dos cinco arquivos alterados e smoke local com cenário real (controles, câmeras, nuvens, zero requests WX). Evidência em /Users/jairo/Documents/Codex/flight-preview-web-check/preview-clouds.png. Publicada em https://flight.marinetcs.com; HTML, worker e bundles públicos verificados byte a byte. Entrada index-BRN5ZiDU.js, CSS index-DjMFdHZO.css, lazy PlanPreview3D-CcgcBQ2c.js. API health OK. Backup /srv/flight/backups/web-20261019-preview3d-before. O smoke interativo pós-publicação não foi repetido: IAB indisponível, sessão real Chrome não utilizada. API e pilhas náuticas sem alterações nesta etapa.

Build iPad 1.0.0 (44) em distribuição via tools/testflight.sh; resultado final será registrado abaixo. Log /tmp/build44-testflight.log.

Distribuição 44 concluída em 19/10/2026 às 19:13 BRT: archive CFBundleVersion=44, xcodebuild informou Upload succeeded / Uploaded Runner / EXPORT SUCCEEDED, saída 0. Apple confirmou que o pacote está em processamento. Disponibilidade aos testadores ainda não verificada. Log /tmp/build44-testflight.log.

### 19/10/2026 — PACK: cinza por padrão, "i" vermelho só com meteorologia atrasada (build 45, Claude)

Web e iPad: o botão PACK fica verde com recibo < 30 min; cinza (pressionável) quando nada é urgente; "i" vermelho só a partir de 60 min antes do ETD explícito (ou em voo, no iPad) com a meteorologia da rota ausente ou com mais de 60 min. Web `packLook` (`lib/nav/routePack.ts`), iPad `PackStore.look`. Publicada a web (backup `/srv/flight/backups/web-20261019-pack-look-before`, index/pack-sw.js conferidos por MD5); TestFlight 1.0.0 (45) enviado (exit 0), Apple processando.
