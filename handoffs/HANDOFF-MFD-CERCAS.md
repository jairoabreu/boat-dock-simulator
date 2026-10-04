# HANDOFF — Cercas no MFD (iVS-LCD7): alerta na tela

Estado: plataforma PRONTA na dev (04/10/26, cartão #389). Falta o lado
do firmware do MFD (contexto `matel-engine-panel/`). Autor do contrato:
sessão da plataforma web.

## O que o produto faz

Na criação/edição da cerca (web náutica) existe o switch **"Alerta no
MFD de bordo"** — terceiro canal de aviso, ao lado de e-mail/WhatsApp.
O MFD baixa as cercas vinculadas à embarcação, desenha quem quiser, e
**alarma na tela** ao entrar/sair das que tiverem `mfd_alert=true`
(respeitando `alert_on_entry`/`alert_on_exit`).

## Contrato da API (dev: https://api-dev.marinetcs.com/api/v1)

**Auth**: token de EQUIPAMENTO (`Authorization: Bearer mtd_…`), o mesmo
canal /hmi da tela 10.1". O token é emitido na plataforma por
`POST /devices/{id}/device-token` (volta UMA vez) e identifica empresa
e embarcação — sem X-Company-Id.

**`GET /hmi/geofences`** →
```json
{
  "versao": "e722940560905e25",
  "items": [
    {
      "id": "uuid",
      "name": "Ponta Leste - Angra",
      "color": "#1E40AF",
      "geometry": { "type": "Polygon", "coordinates": [[[lon, lat], …]] },
      "alert_on_entry": true,
      "alert_on_exit": true,
      "mfd_alert": true,
      "speed_limit_kt": 10.0,
      "updated_at": "2026-10-04T…Z"
    }
  ]
}
```

Semântica:
- O recorte espelha o DETECTOR da plataforma: cercas **ativas** da
  empresa do equipamento; `vessel_ids` vazio na cerca = empresa toda,
  preenchido = só as embarcações listadas (o servidor já filtra — o
  MFD recebe apenas as dele).
- **GeoJSON**: coordenadas em `[lon, lat]` (ordem GeoJSON!), polígono
  com anel fechado (primeiro == último vértice).
- `speed_limit_kt` (nós, 0.5–99, `null` = sem limite): limite de
  velocidade DENTRO da cerca. Independe de `mfd_alert` — limite
  preenchido já vale, mesmo sem o sino de entrada/saída.
- `versao` é hash estável de (ids + updated_at) do conjunto: guarde-a;
  no poll seguinte, se igual, nada mudou (não reprocessar). Cadência
  sugerida: a cada 5 min com a embarcação ligada, e no boot.
- Offline-first: persistir o último conjunto; sem rede, o alarme local
  continua com as cercas baixadas.

## Lado MFD (a implementar lá)

1. Poll `GET /hmi/geofences` (boot + 5 min) com o token mtd_ da tela.
2. Point-in-polygon local com a posição corrente (GPS/CAN): transição
   fora→dentro dispara se `alert_on_entry`; dentro→fora se
   `alert_on_exit` — somente nas cercas `mfd_alert=true`.
3. Alarme na tela no padrão de alarmes do MFD (reconhecível), com
   nome e cor da cerca. Anti-reentrância: histerese/debounce na borda
   (sugestão: ~30 s ou ~50 m) para não metralhar na linha da cerca.
4. A plataforma segue mandando e-mail/WhatsApp pelos canais dela — o
   MFD não precisa reportar o cruzamento (o rastreador já reporta).

## Aviso de velocidade dentro da cerca (speed_limit_kt)

**O dado**: `speed_limit_kt` por cerca (nós, 0.5–99, uma casa
decimal; `null` = cerca sem limite). **Independe de `mfd_alert`**:
limite preenchido já vale, mesmo com o sino de entrada/saída
desligado — são dois avisos distintos.

**A regra**: com a embarcação DENTRO de uma cerca com limite, se a
SOG corrente exceder o limite, o MFD mostra um aviso de velocidade na
tela. Fora da cerca o limite não existe.

**Máquina de estados sugerida** (por cerca com limite):

```
FORA ──entra──▶ DENTRO_OK ──SOG > limite por ≥5 s──▶ EXCEDENDO
  ▲                 ▲                                    │
  └────sai──────────┴──SOG < limite − 0,5 kt por ≥5 s────┘
```

- Disparo com atraso (≥5 s acima) e rearme com folga (limite − 0,5 kt)
  — sem isso, mar mexido vira metralhadora de aviso.
- Ao SAIR da cerca em estado EXCEDENDO, limpar o aviso em silêncio.
- O aviso deve dizer a cerca e o limite (ex.: **"Velocidade acima do
  limite — Marina Piratas (máx. 10 kt)"**) e some sozinho ao
  normalizar; se o padrão de alarmes do MFD pedir reconhecimento,
  reconhecer silencia aquele episódio (novo episódio = novo aviso).

**Casos de borda**:
- **Cercas sobrepostas** com limites diferentes: vale o MENOR limite
  entre as cercas em que a embarcação está; o aviso cita essa cerca.
- **Perda de GPS/posição** dentro da cerca: congelar o estado e NÃO
  alarmar por dado velho; retomando o fix, reavaliar do zero.
- **Limite alterado no poll** (a `versao` mudou): reavaliar o estado
  corrente com o novo valor; se a cerca perdeu o limite (`null`),
  limpar aviso ativo dela.
- **SOG**: usar a mesma fonte de velocidade que o MFD já exibe no
  painel (coerência com o que o operador vê); não suavizar além do
  que o painel suaviza.

## Prova feita na dev (04/10)

Token emitido para o device do Yeshua X; `GET /hmi/geofences` devolveu
2 cercas da empresa (a vinculada a outra embarcação ficou de fora),
"Ponta Leste - Angra" com `mfd_alert=true` após ligar o switch na web
e, depois, com `speed_limit_kt=10.0` gravado pela web — a `versao` do
conjunto girou junto, provando o mecanismo de poll barato.
