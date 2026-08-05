# Marine Telematics — Logos (MaTel)

Pacote de logos da marca para uso no app / plataforma. Todos PNG com **fundo transparente**.

> ⚠ Estes arquivos foram derivados da identidade pública da Marine Telematics. O **wordmark** pode usar uma fonte licenciada/custom — para produção, peça os arquivos vetoriais oficiais (`.svg` / `.ai`) ao time de marca. Use os PNGs abaixo como referência fiel até lá.

---

## Arquivos

| Arquivo | Conteúdo | Dimensões | Usar quando |
|---|---|---|---|
| `logo-wordmark-white.png` | Marca + "Marine Telematics" em **branco** | 1500×152 | Sobre fundos escuros / navy / fotos |
| `logo-wordmark-dark.png` | Marca + wordmark em **navy** | 1500×152 | Sobre fundos claros / brancos |
| `logo-mark-teal.png` | Só o **símbolo** (onda-M) teal | 381×152 | Ícone, favicon, avatar, splash |
| `logo-mark-white.png` | Só o símbolo, **branco** | 381×152 | Símbolo sobre fundo colorido/escuro |
| `logo-mark-navy.png` | Só o símbolo, **navy** | 381×152 | Símbolo sobre fundo claro |

---

## Cores da marca

```
Teal (símbolo)   #1e7a8a
Navy (wordmark)  #0b1f33
Branco           #ffffff
```

---

## Regras de uso

- **Área de proteção:** mantenha um espaço livre de no mínimo a **altura do símbolo** ao redor do logo.
- **Tamanho mínimo:** wordmark ≥ 120px de largura; símbolo ≥ 24px.
- **Não** distorça, gire, aplique sombra/contorno, recolora fora da paleta, nem coloque o wordmark navy sobre fundo escuro (use a versão branca).
- O **símbolo** (onda-M) é o melhor para espaços quadrados/pequenos: ícone do app, avatar da empresa, favicon, marca d'água.

---

## Uso no app (Flutter)

```dart
// pubspec.yaml
//   assets:
//     - assets/logos/

// Wordmark adaptável ao tema
Image.asset(
  Theme.of(context).brightness == Brightness.dark
    ? 'assets/logos/logo-wordmark-white.png'
    : 'assets/logos/logo-wordmark-dark.png',
  height: 28, // largura automática
);

// Símbolo no header / avatar
Image.asset('assets/logos/logo-mark-teal.png', height: 32);
```

## Uso na web

```html
<!-- Wordmark -->
<img src="logos/logo-wordmark-dark.png" alt="Marine Telematics" style="height:28px">

<!-- Símbolo (ícone) -->
<img src="logos/logo-mark-teal.png" alt="MaTel" style="height:32px">
```

Para troca automática claro/escuro na web:
```html
<picture>
  <source srcset="logos/logo-wordmark-white.png" media="(prefers-color-scheme: dark)">
  <img src="logos/logo-wordmark-dark.png" alt="Marine Telematics" style="height:28px">
</picture>
```
