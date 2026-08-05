# Handoff — imagem do barco e logo na tela 10.1"

**Data:** 01/08/2026
**Placa:** ESP32-P4, MAC `80:F1:B2:D3:96:E0`, painel 800×1280 retrato
**Repos:** `matel-ivs-display-p4` (firmware) · `matel-web-platform-api` (plataforma)

> **Resumo em uma linha:** imagem do barco **e logo** resolvidos dos dois lados.
> O que resta é **design**: a orientação da caixa (retrato × paisagem).

---

## 0. Pendências da rodada anterior — ✅ AMBAS FECHADAS (01/08, plataforma)

**1. "Mandar o asset do logo no `/hmi/config`"** — não era o endpoint: a
embarcação da bancada (`NX 50 Invictus - Demonstração`) simplesmente **não tinha
estaleiro vinculado** (`shipyard_logo_id` nulo). A `NX 50 Invictus Fly`, que
tinha, já vinha recebendo o logo normalmente.

O vínculo foi feito no dev, e o config da bancada agora traz os dois:

```json
"assets": [
  {"id": "boat", "url": "…/6a44c8c18ce4edd6.jpg", "bytes": 7970, "w": 360, "h": 134},
  {"id": "logo", "url": "…/d5846dd27b88a7a4.jpg", "bytes": 5251, "w": 304, "h": 108}
]
```

> Como o `config_version` sai de um hash do payload, a mudança se propaga
> sozinha no próximo poll — sem intervenção na tela.

**2. "Conferir se a §3 ainda bate (`w`/`h` × `bytes`)"** — ~~a §3 está correta:
`w` e `h` são servidos, como se vê acima. A captura de vocês era anterior ao
deploy da derivada. Nada a corrigir.~~

> ⛔ **ERRADO — corrigido em 02/08/2026.** Vocês estavam certos: `w` e `h`
> **não** estavam chegando. O endpoint declara `response_model=HmiConfigOut`
> e o FastAPI descarta em silêncio qualquer campo não declarado no schema —
> `HmiAsset` não tinha `w`/`h`. Eu validei o `build_config` isolado (onde o
> JSON acima é real) em vez da resposta HTTP, e por isso afirmei o contrário.
> Corrigido em `matel/schemas/hmi.py` e **verificado pelo endpoint real**;
> junto com `w`/`h` voltaram `area_kind` e todos os campos de tanque —
> detalhes em `HANDOFF-tipos-especiais-tela-10.md`.

**Nada mais pendente do lado da plataforma.** O que falta é **design**, não
implementação — §5. Essa decisão é do Jairo.

## 1. Situação

**Resolvido dos dois lados.** As seções 2 e 3 ficam como registro do problema e
do que a plataforma passou a servir; a 4 conta como o firmware saiu do loop de
reinício. Pendência real: só o formato da caixa (§5).

## 2. Por que o render tinha sido desativado

A tela tem **um único decoder de imagem** — o TJPGD do LVGL, que só abre **JPEG
baseline**. Confirmado no `sdkconfig`:

```
CONFIG_LV_USE_TJPGD=y
# CONFIG_LV_USE_LODEPNG is not set     <- PNG não decodifica
# CONFIG_LV_USE_LIBWEBP is not set     <- WebP não decodifica
# CONFIG_LV_USE_BMP / GIF is not set
```

> O comentário no firmware que cita "LODEPNG p/ .png" descreve uma **intenção**;
> o decoder nunca foi habilitado.

Servir o original quebrava de quatro formas ao mesmo tempo:

| # | Problema |
|---|---|
| 1 | **Formato** — 3 dos 6 assets são `.webp`/`.png`, sem decoder na tela |
| 2 | **JPEG progressivo** — o TJPGD só faz baseline |
| 3 | **Memória** — 1366×768 decodificado pede ~2 MB no heap do LVGL |
| 4 | **Tamanho** — o firmware corta o download em `HC_ASSET_MAX` = 512 KB |

## 3. ✅ Lado da plataforma — RESOLVIDO (no dev)

`matel/services/hmi_assets.py` (novo) gera uma **derivada** por asset, cacheada
em disco ao lado do original. O original fica **intocado** — a web segue usando
ele. O `/hmi/config` passa a apontar para a derivada e traz também `w`/`h`.

**Pipeline:** máscara → recorte → composição → JPEG baseline

1. **Máscara de conteúdo** — usa o alfa quando existe; sem alfa, flood-fill a
   partir das 4 quinas. Só remove fundo **conectado à borda**, para não apagar
   uma parte clara no meio do casco.
2. **Recorte na moldura do conteúdo**, antes de reduzir.
3. **Composição** sobre cor sólida (JPEG não tem canal alfa).
4. **JPEG baseline** (`progressive=False`), reduzido à caixa.

Asset que não converte (SVG, corrompido) é **omitido** do `/hmi/config` em vez de
servido — melhor o placeholder do que falha de decodificação a cada boot.

### Medições reais

| Asset | Origem | Derivada |
|---|---|---|
| NX 50 Invictus Fly | webp 1000×702 RGBA | 360×164 · 10,0 KB |
| Bancada Boat Show | jpg 1366×768 RGB (fundo branco) | 360×134 · 7,8 KB |
| Paula Solaris | png 1376×654 RGBA | 360×151 · 7,6 KB |
| NX Demonstração | jpg 1366×768 RGB (fundo branco) | 360×134 · 7,8 KB |
| Logo NX Boats | webp 312×130 RGBA | 304×108 · 2,5 KB |

Servido em `HTTP 200 · image/jpeg · SOF0 presente · SOF2 ausente`.
Decodificado agora pede ~180 KB em RGB565, contra os ~2 MB de antes.

### Fundo do logo é escolhido por contraste, automaticamente

A arte da **NX Boats é preto puro** (luminância 0): sobre o fundo escuro da tela
dá 22 de diferença e o logo **desaparece**; sobre placa clara dá 245. A do
**VCat é prata** (159) e fica melhor no escuro (138 contra 85).

Nenhuma configuração global serve aos dois, e a escolha é medível — então é
automática. **Não recolore nem inverte** (destruiria um logo colorido); só
escolhe onde pousar.

### Variáveis de ambiente

| Variável | Padrão | Para quê |
|---|---|---|
| `HMI_ASSET_MAX_W` / `_H` | 360 / 480 | caixa alvo — **ajustar quando o layout fechar** |
| `HMI_ASSET_BG` | `#07182A` | fundo da tela (`H_BG` em `hmi.c`) |
| `HMI_ASSET_BG_LOGO_ALT` | `#F2F5F7` | placa clara para logo escuro |
| `HMI_ASSET_CONTRASTE_MIN` | 60 | abaixo disso troca para a placa |
| `HMI_ASSET_REMOVE_BG` | 1 | desligar se entrar foto com cenário |
| `HMI_ASSET_AUTOCROP` | 1 | recorte no conteúdo |
| `HMI_ASSET_BG_TOL` | 18 | tolerância do flood-fill |
| `HMI_ASSET_PAD_PCT` | 2 | margem após o recorte |
| `HMI_ASSET_QUALITY` | 85 | qualidade do JPEG |

⚠️ A chave do cache inclui **todos** esses parâmetros. Mudar qualquer um
regenera as derivadas sozinho.

## 4. ✅ Lado do firmware — RESOLVIDO (01/08/2026)

Eram **três** causas — as duas primeiras somadas (por isso subir a pilha "não
resolveu sozinho": cada tentativa corrigia metade), e a terceira só visível
depois, quando a imagem já desenhava.

**Causa 1 — o decode rodava na task do LVGL.** E não uma vez: o TJPGD entrega a
imagem **por faixas** (`get_area`), então o workspace dele voltava ao caminho de
desenho a cada invalidação. `main/asset_img.c` (novo) decodifica **uma vez**, em
task própria de 24 KB, percorrendo as faixas (foram 299) e montando a imagem
inteira na PSRAM. A UI recebe um `lv_image_dsc_t` pronto e só faz blit — o TJPGD
nunca mais entra no caminho de desenho.

> Detalhe que custou uma tentativa: `lv_image_decoder_open()` devolve
> `dsc->decoded == NULL` para JPEG. Não é erro — é o decoder avisando que a
> imagem sai por `lv_image_decoder_get_area()`.

**Causa 2 — 6 KB não bastavam nem sem o decode.** Medido, não chutado
(`uxTaskGetStackHighWaterMark` agora loga a folga no `lvgl_port_task`): só o
desenho da imagem **escalada** consome ~8 KB. A task foi para 16 KB e o pior
caso medido ficou em **8092 bytes livres**.

A guarda do item 4 da lista antiga entrou junto: `lv_image_decoder_get_info()`
antes de alocar qualquer coisa, recusando acima de 1 MP com log.

**Causa 3 — o formato de pixel estava presumido.** A montagem das faixas fixava
RGB565; o TJPGD entrega **RGB888** (`lv_tjpgd.c:207`). Cada linha saía truncada
em 2/3 e com os canais deslocados: a imagem desenhava, mas **ilegível**. O
tamanho alocado denunciava — `96480 = 360×134×2`, quando o certo é
`144720 = ×3`.

> Armadilha: o `cf` **não** pode vir do `lv_image_decoder_get_info()`, que
> reporta `LV_COLOR_FORMAT_RAW` (`lv_tjpgd.c:117`). O formato real só aparece
> em `dsc->header` **depois** do `lv_image_decoder_open()`.

**Verificado na placa:** 0 panics, imagem legível, derivada com fundo recortado.

### O logo — ✅ desbloqueado

O slot existe (sob a caixa do barco, 320×120). Não pinta fundo próprio — a
derivada já vem sobre a placa de contraste — e **não amplia** arte menor que o
slot, só reduz.

O asset **já chega** desde que o estaleiro foi vinculado à embarcação (§0). O
logo NX Boats vai em `304×108`, 5251 bytes, sobre a placa clara `#F2F5F7`
escolhida por contraste — a arte é preto puro e sumiria no fundo escuro.

**Visto na placa** — os dois assets desenham:

```
asset_img: barco pronto: 360x134, 144720 bytes na PSRAM
asset_img: logo  pronto: 304x108,  98496 bytes na PSRAM
hmi: imagem do barco desenhada: 360x134 -> caixa 360x480
hmi: logo do estaleiro desenhado: 304x108 -> slot 320x120
```

### Commits do firmware

| Commit | O quê |
|---|---|
| `a818f3e` | decode fora da task do LVGL + pilha 16 KB — imagem do barco na tela |
| `759b95f` | slot do logo; `boat_img.c` → `asset_img.c`, decode multi-slot |
| `21efd5b` | formato de pixel lido do decoder (RGB888) — **imagem legível** |

## 5. Para o design novo (em andamento)

| Item | Valor atual |
|---|---|
| Painel | 800×1280, retrato |
| Caixa do barco | **360×480**, raio 180 (cápsula), borda 2 px |
| Fundo da caixa | `#123244` a 30% de opacidade sobre `H_BG` = `#07182A` |
| Logo | slot **320×120**, sob a caixa do barco (§4) — desenhando |

**⚠️ A caixa é retrato e as imagens cadastradas são paisagem.** Depois do
recorte o NX 50 Invictus fica `360×164` numa caixa de `360×480` — uma faixa no
meio de muito espaço vazio. Decidir isso primeiro, porque muda a arte que se
pede ao estaleiro: ou a caixa vira paisagem, ou os diagramas passam a ser vista
de topo (retrato).

**Sem transparência:** JPEG não tem canal alfa. Se o design mudar a cor de
fundo, ajustar `HMI_ASSET_BG` — senão o recorte aparece sobre a cor errada.

**Ao fechar o layout, passar as caixas em pixels.** A plataforma pré-dimensiona
no servidor e a tela recebe pronto, sem escalar nada.

## 6. Commits

| Repo | Commit | O quê |
|---|---|---|
| `matel-web-platform-api` | `f04e263` | derivada JPEG baseline no `/hmi/config` |
| `matel-web-platform-api` | `7e9740d` | remoção de fundo, recorte e fundo do logo por contraste |
| `matel-ivs-display-p4` | `dd0a23e` | **revert** da tentativa de religar o render |
| `matel-ivs-display-p4` | `a818f3e` | decode fora da task do LVGL + pilha 16 KB — **imagem na tela** |
| `matel-ivs-display-p4` | `759b95f` | slot do logo; `boat_img.c` → `asset_img.c` multi-slot |
| `matel-ivs-display-p4` | `21efd5b` | formato de pixel lido do decoder (RGB888) — **imagem legível** |

> Além dos commits: no dev, `NX 50 Invictus - Demonstração` passou a ter o
> estaleiro **NX Boats** vinculado — era o que faltava para o logo chegar à
> bancada. É dado, não código; reversível zerando `vessels.shipyard_logo_id`.
