# Handoff — formato de imagem para a tela 10.1" (PNG com transparência)

**Data:** 02/08/2026 · **Firmware:** `matel-ivs-display-p4` (branch `feature/nav-n2k-travessia`)
**Para:** plataforma web (`matel-web-platform-api`, pipeline `matel/services/hmi_assets.py`)

> **Resumo em uma linha:** a tela agora decodifica **PNG com canal alfa**
> (LODEPNG habilitado) — as derivadas de barco e logo devem migrar de JPEG
> para PNG transparente, nos tamanhos abaixo, e o fundo/placa de contraste
> deixam de ser necessários.

---

## 1. O que mudou na tela

- **Decoder PNG habilitado** (`LV_USE_LODEPNG`). O roteamento é por
  **extensão do arquivo**: URL terminando em `.png` → LODEPNG; `.jpg` →
  TJPGD (continua funcionando como fallback).
- O decode roda **uma vez, fora do caminho de desenho** (task própria), então
  o custo de decodificar PNG não afeta a fluidez.
- A tela **pré-escala** a imagem do barco uma única vez (bilinear) e depois só
  faz blit — a resolução servida importa para nitidez, não para desempenho.
- Logo **escuro** no tema noite é **recolorido para branco** pela tela (o
  recolor preserva o alfa). A placa de contraste clara que o pipeline embutia
  na derivada JPEG **não deve mais ser aplicada** na variante PNG.

## 2. Especificação das derivadas

### 2.1 Imagem da embarcação (`id: "boat"`)

| Parâmetro | Valor |
|---|---|
| Formato | **PNG RGBA** (alfa preservado, sem compor sobre cor) |
| Largura | **720 px** (a tela desenha a 700; nunca amplia além de 2×) |
| Altura | proporcional (paisagem; livre) |
| Entrelaçamento | **não** (progressive/Adam7 desnecessário) |
| Fundo | **transparente** — sem placa, sem cor de composição |
| Autocrop | pode manter, **mas ver §3 (posições!)** |
| Limites rígidos | ≤ 512 KB (corte de download do firmware) · ≤ 1 MP (recusa) |

Um casco 720×~270 em PNG-24 fica tipicamente em 60–150 KB — folgado.

### 2.2 Logo do estaleiro (`id: "logo"`)

| Parâmetro | Valor |
|---|---|
| Formato | **PNG RGBA** |
| Largura | **360 px** (a tela exibe a ≤180 — só reduz, nunca amplia) |
| Fundo | **transparente**, **sem placa de contraste** |
| Placa clara p/ logo escuro | **remover do pipeline** — a tela resolve por recolor |

O ideal para logos monocromáticos (caso NX, preto puro): servir na cor
original com alfa. No tema noite a tela tinge de branco; no tema dia exibe a
cor original sobre fundo claro.

## 3. ⚠ Posições dos cômodos × autocrop

Os `pos_x`/`pos_y` das áreas são interpretados como **percentual do retângulo
da imagem servida**. Se o pipeline recorta (autocrop) antes de gerar a
derivada, as posições **precisam ser medidas sobre a imagem já recortada** —
senão todos os pontos aparecem deslocados de forma sistemática na tela.

Regra prática: o frame de referência do editor de posições da plataforma deve
ser **exatamente a derivada servida**, não o original.

## 4. O que NÃO servir

- JPEG **progressivo** (o TJPGD só faz baseline) — vale para o fallback.
- WebP, SVG, GIF, BMP — sem decoder na tela.
- Acima de **1 megapixel** — o firmware recusa antes de alocar.
- PNG paletado com transparência via tRNS funciona, mas RGBA direto é o
  caminho testado.

## 5. Contrato de entrega (inalterado)

O `/hmi/config` continua igual: `assets[]` com `id`, `url`, `sha256` — a tela
rebaixa quando o sha muda e **preserva a extensão da URL** ao salvar (é ela
que escolhe o decoder). Basta a URL da derivada passar a terminar em `.png`.

## 6. Comportamento da tela (referência)

| Item | Valor |
|---|---|
| Área útil da lancha | 700 × 430 px (paisagem 1280×800) |
| Escala | uniforme, teto 2×, bilinear, uma vez |
| Hotspots | `pos_x`/`pos_y` em % sobre o retângulo da imagem |
| Logo | ≤180 px de largura, ~10 px acima do casco, centrado |
| Tema noite | logo escuro → recolorido branco (alfa preservado) |
| Tema dia | logo na cor original |
