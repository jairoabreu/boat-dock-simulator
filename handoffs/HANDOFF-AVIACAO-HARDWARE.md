# HANDOFF — MaTel Aviation: hardware e firmware (para o GPT)

17/10/2026 · de: Claude (app iPad + plataforma web) · para: GPT (firmware + PCB)

## 0. Divisão de trabalho (decisão do Jairo, 17/10/2026)

| Quem | O quê | Onde |
|---|---|---|
| **GPT** | Firmware e PCB/hardware: caixa portátil MaTel NAV e módulo de motor | `~/MaTel/matel-aviation-fw/` (+ pasta de PCB a criar) |
| **Claude** | App do iPad e plataforma (API + site) | `~/MaTel/matel-aviation-app/`, `~/matel-api-aviacao` (branch `feat/aviacao`), `~/MaTel-web-aviacao` (branch `feat/aviacao-web`) |

A fronteira são os **contratos Bluetooth** (§3). Firmware e app são escritos de
lados diferentes e precisam bater **byte a byte**. Qualquer mudança num contrato
segue a regra do §3.5.

## 1. O produto

1. **Caixa MaTel NAV (portátil)** — equivalente brasileiro do Sentry Plus.
   Fica no painel, roda à bateria, liga no iPad por Bluetooth e:
   - dá posição (GPS), atitude (AHRS) e altitude-pressão (barômetro);
   - grava o voo inteiro, mesmo sem o iPad;
   - mais tarde: tráfego ADS-B In (1090ES) e celular/LTE para rastreamento sem o iPad.
2. **Módulo de motor** (2ª etapa) — ligado à saída serial do motor do Cirrus
   (Avidyne SIU / DAU), **só recepção**, manda os dados do motor ao iPad.
   O firmware dele já existe e funciona em bancada (§2).
3. **App MaTel Aviation (iPad)** — navegação, 3D, alerta de terreno, plano de
   voo, gravação automática do voo e diário de bordo eletrônico (Res. ANAC 773).
4. **Plataforma web** (flight.marinetcs.com) — frota ao vivo, voos com replay e
   motor, diário de bordo com volumes e assinaturas.

Contexto de mercado: `matel-aviation-app/docs/visao-e-mercado/MaTel_Aviation_Visao_e_Mercado_2026-10.pdf`.
No Brasil **não existe** meteorologia/tráfego por ADS-B em solo (FIS-B/TIS-B é
dos EUA). O valor da caixa aqui é GPS + AHRS + barômetro + gravação. ADS-B In
só faz sentido em 1090ES (tráfego ar-ar).

## 2. Estado atual de `matel-aviation-fw`

Build: ESP-IDF via PlatformIO, `env:esp32-s3-devkitc-1` (`platformio.ini`,
`CMakeLists.txt`, componente `main/`). Plano de arquitetura do módulo de motor
em `PLAN.md`.

| Commit | Conteúdo |
|---|---|
| `3390023` | Gateway de telemetria de motor ESP32-S3 → BLE |
| `a507130` | Build PlatformIO, replay de motor, correções de BLE (testado de ponta a ponta no iPad) |
| `5c5f925` | Serial real **19200** (DAU) — saiu do modo replay; getter de frames válidos |
| `d554386` | `main/nav_wire.h` — contrato das mensagens de navegação da caixa (só o contrato) |

- **Módulo de motor:** `avidyne_parser.c`, `serial_source.c`, `engine_gateway.c`,
  `ble_gateway.c`, `engine_wire.c/.h`. Funciona, mas **ainda não foi instalado no avião**.
  Atenção: o `PLAN.md` fala em SIU 9600 8N1; o último commit passou para 19200
  (DAU). Confirme a velocidade na aeronave antes de instalar.
- **Caixa NAV:** só o contrato `nav_wire.h`. O firmware de GPS/AHRS/baro está
  **por fazer**. Hoje a caixa inteira é simulada por ferramentas do app (§5).
- **Peças do protótipo** (compradas ou sendo compradas pelo Jairo): GPS u-blox
  NEO-6M, IMU MPU-6500 (vendida como MPU-9250), magnetômetro LSM303DLHC,
  barômetro BMP180, placa ESP32-S3. São peças de protótipo; para a PCB
  recomendamos GPS da série M8/M10 com SBAS a 5–10 Hz e um barômetro
  BMP388/BMP390 ou similar.

## 3. Contratos Bluetooth (fonte da verdade)

UUIDs base `xxxxxxxx-4d54-4156-4961-74696f6e0001`. Tudo **little-endian**.

### 3.1 Serviço e características

| UUID | Nome | Propriedades | Conteúdo |
|---|---|---|---|
| `0000a7e0-…` | Serviço MaTel Aviation | — | anunciado no advertising (o app faz scan por ele) |
| `0000a7e1-…` | Schema (motor) | read + notify | `engine_wire.h` → `ew_pack_schema()` |
| `0000a7e2-…` | Data (motor) | notify | `ew_pack_data()` |
| `0000a7e3-…` | Status (motor) | read + write + notify | `ew_pack_status()` (15 B) |
| `0000a7e4-…` | **NAV** (caixa) | notify | mensagens `nav_wire` (§3.2) |

O protocolo do motor está documentado no cabeçalho de `main/engine_wire.h` e
decodificado no app em `lib/ble/engine_wire.dart`.

### 3.2 `nav_wire` — mensagens da caixa (NAV)

Cada notificação leva uma ou mais mensagens `[u8 tipo][u8 len][payload]`. O app
**pula tipos desconhecidos pelo `len`**, então o formato cresce sem quebrar.

| Tipo | Nome | Len | Payload |
|---|---|---|---|
| `0x01` | POS | 24 | u8 flags (b0 fix, b1 3D, b2 airborne) · u8 sats · i32 lat 1e-7° · i32 lon 1e-7° · i32 altitude GPS MSL **dm** · u16 GS **cm/s** · u16 trilha 0,01° · i16 VS cm/s · u16 hAcc dm · u16 seq |
| `0x02` | ATT | 12 | u8 flags (b0 válido, b1 tem proa, b2 proa magnética, b3 alinhando) · u8 reservado · i16 rolagem 0,01° (**+ = asa direita baixa**) · i16 arfagem 0,01° (**+ = nariz para cima**) · u16 proa 0,01° · i16 derrapagem mg · i16 razão de curva 0,01°/s |
| `0x03` | BARO | 8 | u8 flags (b0 válido) · u8 reservado · i32 altitude-pressão **dm** (1013,25 hPa) · i16 VS cm/s |
| `0x7F` | ID | ≤ 40 | u8 versão · u8 caps (b0 GPS, b1 AHRS, b2 baro, b3 tráfego, **b7 simulador**) · nome UTF-8 |

Implementações de referência: `matel-aviation-fw/main/nav_wire.h` (empacotadores
em C) e `matel-aviation-app/lib/sensors/nav_wire.dart` (decoder +
encoder usado pelo simulador e pelos testes, `test/nav_wire_test.dart`). As
duas foram conferidas byte a byte em 13/10.

### 3.3 O que o app espera do firmware

- **Frequências:** POS a pelo menos 1 Hz (ideal 5 Hz); ATT a 10–20 Hz; BARO a
  ~5 Hz; ID ao conectar/inscrever e depois a cada ~5 s. Junte várias mensagens
  numa notificação quando couber no MTU.
- **Validade:** o app considera posição e atitude "vivas" por **4 s** após a
  última mensagem (`MatelBox.fixFresh`/`ahrsFresh`). Sem fix, mande POS com
  `fix=0` (o app mostra o motivo), não pare de mandar.
- **ATT:** com `aligning=1` ou `valid=0` o app **não desenha atitude** (mostra o
  X vermelho de AHRS falho). Proa verdadeira com b2=0; magnética com b2=1.
- **Sinais e unidades:** exatamente como na tabela (§3.2). Erros de sinal na
  rolagem/arfagem viram horizonte artificial invertido — teste com a tela AHRS do app.
- **`caps.simulator` (b7) NUNCA** no hardware real: é como o app reconhece o
  simulador do Mac.
- **airborne (POS b2):** opcional; o app hoje decide voo por GS/VS (gravador).
  Se for implementar: GS > 40 kt e altura > 50 ft acima do ponto de partida.
- **hAcc:** precisão horizontal estimada pelo GPS (u-blox `hAcc`), em dm.

### 3.4 Dois equipamentos separados (caixa NAV + módulo de motor)

Até agora tudo era **uma caixa só** (motor + NAV no mesmo serviço e conexão).
Com dois aparelhos:
- os dois anunciam o serviço `0000a7e0-…`;
- a caixa NAV expõe **só** NAV (`a7e4`); o módulo de motor expõe **só**
  Schema/Data/Status (`a7e1–a7e3`);
- nomes no advertising: `MaTel-NAV-XXXX` e `MaTel-ENG-XXXX` (XXXX = final do MAC);
- o ID (`0x7F`) da caixa NAV leva `caps` sem tráfego até o ADS-B existir.

**Lado do app (Claude):** hoje o app se conecta ao **primeiro** aparelho que
anuncia o serviço. Ele será adaptado para conectar aos dois ao mesmo tempo,
pelo que cada um expõe. Até essa versão do app sair, **não ligue os dois
juntos**. Avisem quando o primeiro protótipo separado existir.

### 3.5 Regra para mudar um contrato

1. Não mude o significado nem o tamanho de campos existentes. Para crescer,
   **acrescente um tipo novo** (ou campos no fim com `len` maior, que o app antigo ignora).
2. Atualize **juntos** `main/nav_wire.h` / `main/engine_wire.h` e este handoff (§3).
3. Avise o Jairo para o Claude atualizar o decoder do app
   (`lib/sensors/nav_wire.dart`, `lib/ble/engine_wire.dart`) e os testes.

## 4. Próximas entregas sugeridas (GPT)

1. **Fase 1 — GPS:** NEO-6M (UBX, 5 Hz) → POS + ID na característica NAV. Testar
   no app: SETUP › NAV › Posição = MATEL; o mapa deve mostrar o avião e "MATEL" em verde.
2. **Fase 2 — AHRS:** MPU-6500 + LSM303 → ATT, com correção de curva pelo GPS
   (aceleração centrípeta), alinhamento no solo (`aligning`) e derrapagem/razão de curva.
3. **Fase 3 — Barômetro:** BMP180 → BARO (altitude-pressão em dm, VS).
4. **Gravador de voo a bordo:** gravar POS/ATT/BARO (e motor, quando houver) em
   flash/SD, independente do iPad. A descarga para o iPad/plataforma precisa de
   um **contrato novo** (tipo TLV novo ou característica nova): propor aqui
   antes de implementar, para o app e a plataforma acompanharem.
5. **PCB rev 1 e caixa:** bateria (alvo ≥ 8 h), carga USB-C, antena GPS,
   montagem no painel/glareshield, LED de estado.
6. **Depois:** ADS-B In 1090ES (receptor com saída UART) → novo tipo de mensagem
   de tráfego; LTE para enviar o voo direto à plataforma (ver §6).

## 5. Como testar contra o app sem a caixa

No `matel-aviation-app`:
- `dart run tools/box_sim.dart --ble` + `tools/ble_bridge.swift`: o Mac anuncia
  como a caixa (serviço `a7e0` + NAV) e voa uma rota inteira (decolagem, rota,
  pouso). É a referência de comportamento: o firmware deve produzir o mesmo
  tipo de fluxo. O empacotamento do simulador usa `lib/sensors/nav_wire.dart`.
- `flutter test test/nav_wire_test.dart`: os casos de decodificação.
- O app em TestFlight já tem as telas para validar: mapa (MATEL verde), AHRS
  (horizonte), altitude/GS nas fitas, gravação automática no LOG BOOK.

## 6. Plataforma (para quando a caixa tiver LTE)

Hoje o iPad envia o voo à plataforma usando um **token de equipamento**
(pareamento iPad ↔ aeronave em SETUP › CONTA). Uma caixa com LTE poderia usar
o mesmo caminho:
- `POST https://flight.marinetcs.com/api/v1/aviation/live`
  - cabeçalho `Authorization: Bearer mtd_…`
  - corpo `{"flight_id": "<uuid>", "pts": [[t, lat, lon, alt_ft, gs_kt, trk_deg, vs_fpm], …]}`
    (t em segundos epoch; a resposta traz `ack_t`, o último ponto gravado);
- `PUT …/aviation/flights/{uuid}` com o voo completo.

O pareamento da **caixa** (não do iPad) ainda não existe na API; fica para
combinar com o Claude quando chegar a hora.

## 7. Regras que valem para o hardware

- **Consultivo, não certificado.** Nada aqui é instrumento primário.
- **Motor: só recepção.** Y-tap passivo, RX + GND, nunca transmitir na linha do
  avião (manual Avidyne 600-00073, Apêndice O).
- **Sem engenharia reversa de protocolos de terceiros** (por exemplo Sentry/uAvionix
  ou ForeFlight). O caminho é o hardware e o protocolo próprios da MaTel.
- **ANATEL:** um produto com rádio (BLE, depois LTE) precisa de homologação.
  Use módulos já homologados quando possível.
