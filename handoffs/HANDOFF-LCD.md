# Handoff — MFD nas telas 7" e 10.1" (matel-engine-panel)

Contexto: adaptação do firmware MFD completo (menus, Start-Stop, instrumentos,
mapa/cercas, cliente da plataforma) da tela 7" para a 10.1", feita e commitada;
resta UM problema aberto (touch lento na 10.1") e as fases seguintes.

## Hardware (2 placas ESP32-P4 Guition)

| | 7" | 10.1" (JC8012P4A1C) |
|---|---|---|
| Painel | JD9165, 1024×600 **paisagem nativa** | JD9365, 800×1280 **retrato nativo** (UI gira 90° por sw → 1280×800) |
| Touch | GT911 (I2C, RST/INT=NC) | GSL3680 (I2C 0x40 @100 kHz, RST=GPIO22, INT=GPIO21) |
| Porta USB no Mac | `/dev/cu.usbmodem*` (USB nativo) | `/dev/cu.usbserial-*` (CH340) |
| Estado | ✅ restaurada, MFD ok (build padrão) | ✅ vídeo perfeito; ⚠️ **touch lento (problema aberto)** |

⚠️ **Nunca gravar firmware de uma na outra.** Já causou falso diagnóstico de
"tela morta": com driver errado o painel devolve `LCD ID: 00 00 00` e o boot
trava em watchdog. Painel saudável responde `LCD ID: 93 65 04` (JD9365).
Binários de fábrica p/ recuperação: `matel-p4-docs/.../8-Burn operation/Burn files/`
(gravar em 0x0; a 7" NÃO usa esses — o firmware dela é o próprio matel-engine-panel).

## Repo `matel-engine-panel` — porte pra 10.1" (commits feitos)

- Seleção de placa: `CONFIG_MFD_BOARD_LCD10` (Kconfig.projbuild) condiciona
  painel/touch/pinos em `main/main.c`, resolução em `main/lvgl_port_v9.h`
  (`LVGL_PORT_H/V_RES` nativos + `UI_DISP_W/H` e `UI_BODY_H` lógicos usados
  pelas telas — nada mais de 1024/600/540 fixo na UI).
- Tabela de init do painel: `main/jd9365_10_init.h` (copiada do bring-up
  validado em `matel-ivs-display-p4`). Touch: `components/esp_lcd_touch_gsl3680`.
- Build 10.1": `idf.py -B build_lcd10 -DSDKCONFIG=sdkconfig.b10 -DSDKCONFIG_DEFAULTS="sdkconfig.defaults;sdkconfig.lcd10" build`
- Build 7" (inalterada): `idf.py build`
- Fixes commitados: DSI lane **1500 Mbps** no LCD10 (750 = metade chuvisco/
  metade preta), resolução no port, layout via `UI_BODY_H` (corrigiu o
  Start-Stop vazando na base), **beep desabilitado no LCD10** (pinagem de
  áudio difere da 7"; ligado, o I2S trava em loop e estrangula o LVGL —
  mapear codec/pinos nos esquemáticos `matel-p4-docs` para religar).

## ⚠️ PROBLEMA ABERTO: touch da 10.1" lento (teclados inutilizáveis)

Sintoma: botões grandes ok; **teclados perdem taps rápidos** — tocar uma
tecla e outra em seguida, a segunda não registra.

Medições (instrumentação DIAG em `touchpad_read` no `main/lvgl_port_v9.c`,
ainda presente no working tree — remover ao final):
- Leitura GSL3680 = **~2,5 ms/poll**, estável, sem travadas (max 3,4 ms).
- Com INT habilitado, só **8/100 polls** reportavam press com dedo na tela.
- Janelas de 100 polls esticam de 2,0 s → 3,75 s durante interação
  (render/afins roubam o loop do LVGL).

Já tentado (mudanças **não commitadas** no working tree):
1. Indev 33→10→**20 ms** (`lv_timer_set_period` no `indev_init`) — pouco efeito.
2. LVGL task no core 1 prio 5 — **piorou** (core 1 tem carga própria), revertido
   p/ `TASK_CORE=-1`, prio 5 mantida no `sdkconfig.b10`.
3. `int_gpio_num = GPIO_NUM_NC` (polling puro) — **melhorou botões** (mantido).
4. Avoid-tear OFF — **quebra a rotação** (o caminho de tear carrega a rotação
   sw/PPA): tela fica vertical e touch desmapeado. Revertido.
5. Avoid-tear **modo 3 (direct)** — melhorou algo, mantido no `sdkconfig.b10`
   (⚠️ ainda não replicado no `sdkconfig.lcd10` defaults).
6. Heurística split de taps (salto >80 px/poll sintetiza RELEASED em
   `touchpad_read`) — **não resolveu**.

Próximas hipóteses (em ordem sugerida):
1. Medir a **taxa de reporte do próprio GSL3680** (blob `gsl_point_id`) — se o
   chip só entrega pontos novos a ~10 Hz, nenhum tuning de LVGL salva; olhar
   o driver `components/esp_lcd_touch_gsl3680/esp_lcd_gsl3680.c` (nota: boot
   loga `startup_chip failed read 0xb0 = 5a,5a,5a,5a` — tolerado, mas suspeito).
2. Subir o I2C do touch para **400 kHz APÓS o upload do fw** (100 kHz só é
   exigido durante o upload; leitura cai de 2,5 ms → ~0,6 ms).
3. Conferir se esta 10.1" tem variante **GT911** (docs mencionam GSL3680/GT911;
   um probe I2C no addr do GT911 resolve a dúvida).
4. Comparar sensação no firmware `matel-ivs-display-p4` (mesmo driver/painel,
   UI leve): taps simples funcionavam — bom baseline A/B.

## Fases seguintes (após touch ok)

1. **Integrar o módulo de Rotas no MFD** como item de menu. Componentes prontos
   e testados no repo `matel-ivs-display-p4`, branch `feature/nav-n2k-travessia`
   (local, sem push):
   - `components/nav_n2k` — núcleo navegação great-circle (rumo/DTW/XTE, avanço
     de waypoint) + encoders NMEA 2000 (129284/129283/60928, fast-packet) +
     `n2k_service` (TWAI 250k, address-claim, RX posição 129025, TX 1 Hz).
     43 testes de host (`components/nav_n2k/test/`, `make run`).
   - `components/crossing_route` — fetch WiFi (`GET /api/v1/crossings/active`
     com `Authorization: Bearer mtd_…`), parse cJSON, cache offline NVS,
     `travessia_data` (task de fundo). 25 testes de host.
   - `main/screen_travessia.c` — tela LVGL de referência (lista → detalhe com
     vetores + botões Iniciar / Compartilhar N2K separados + status N2K).
   - Decisões travadas: Iniciar e Compartilhar N2K são botões separados;
     posição do barco vem do barramento N2K (129025); transceiver CAN externo
     (SN65HVD230) com GPIOs a definir em `main/travessia_cfg.h` (hoje TX=2 RX=3).
   - Cuidado aprendido: `route_list_t` tem ~15 KB — **nunca na pilha de task**
     (já causou stack overflow; usar static/heap).
2. Religar o **beep** da 10.1" (mapear ES8311/pinos nos esquemáticos).
3. Bench NMEA 2000 com piloto automático real (após transceiver soldado).

## Plataforma web (já pronta p/ consumo da tela)

- `GET /api/v1/crossings/active` autenticado por token de equipamento
  (`mtd_…`), inclui rotas do barco + company-wide (vessel nulo). No ar no dev.
- Token gerado em: Gerenciar → Dispositivos → editar o device do barco →
  "Token da tela embarcada" → Gerar (mostrado uma vez).
- Provisionamento da tela: NVS namespace `route` (chaves url/token/ssid/pass —
  ver `route_store.c`); `#define TRAV_BENCH_PROVISION` em `travessia_cfg.h`
  grava na bancada. Se SSID vazio, reaproveita o WiFi já salvo no device.
- WiFi de teste: a 10.1" conecta sozinha em 'Marine_Vivo' (config do MFD).
