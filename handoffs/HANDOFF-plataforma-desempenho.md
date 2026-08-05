# Handoff — desempenho da plataforma visto do equipamento (medições reais)

**Data:** 03/08/2026 · **De:** firmware da tela 10.1" (`matel-ivs-display-p4`)
**Para:** plataforma web (`matel-web-platform-api`) / infraestrutura
**Contexto:** rede WiFi da empresa (boa), servidor `api-dev.marinetcs.com`

> **Resumo em uma linha:** o `api-dev` hiberna e a primeira requisição depois
> de ocioso leva **30–60 s** — nenhum prazo de tela salva um servidor que
> demora um minuto para acordar. Em produção a instância **não pode dormir**,
> e há três melhorias baratas que cortam o tráfego dos barcos em ~95%.

---

## 1. As medições (03/08/2026, mesma rede, mesmo dia)

O firmware agora cronometra todo GET e deixa no log (`hmi_cloud: GET N bytes
em M ms`). Números colhidos hoje:

| Requisição | Tamanho | Tempo | Condição |
|---|---|---|---|
| `GET /api/v1/hmi/config` | 13.008 B | **47.991 ms** (http 200!) | primeira após ocioso — *cold start* |
| `GET /api/v1/hmi/config` | 13.008 B | 11.188 ms | segunda, minutos depois |
| `GET /api/v1/hmi/config` | 13.008 B | 2.045 ms | servidor "quente" |
| `GET /uploads/...boat.png` | 92.203 B | ~16 s (**≈ 6 KB/s**) | download de asset |

O mesmo endpoint, o mesmo payload, variando **23×** conforme o humor do
servidor. Não é rede: o WiFi estava estável e o TLS fecha em ~1 s.

## 2. O que isso causou no produto

O operador apertava **ATUALIZAR DADOS** com WiFi ótimo e lia *"Não consegui
falar com a plataforma"* — porque o prazo da tela (30 s) era **menor que o
cold start**. O sucesso chegava 1,6 s depois da mensagem de falha, invisível.

A tela já se defendeu (prazos 60/120 s, "ainda baixando..." enquanto a busca
corre, uma retentativa antes de acusar falha, duração no log), mas isso é
paliativo. **A percepção de qualidade do produto é limitada pelo pior tempo de
resposta do servidor** — e barco de cliente vai falar com a produção por 4G,
onde cada segundo e cada byte custam mais que no WiFi da empresa.

## 3. Pedidos, em ordem de impacto

### 3.1 Produção sem hibernar (o essencial)

A instância de produção não pode fazer *scale-to-zero* / sleep. Se a
hospedagem atual dorme por inatividade, as opções conhecidas:

- plano/instância *always-on* (o certo para produto);
- ou, no mínimo, um *keep-warm* (ping de saúde a cada poucos minutos) — remendo,
  mas elimina o cold start visível.

Se o **api-dev** continuar hibernando, tudo bem — é dev — mas que fique
registrado que toda primeira interação do dia com a tela vai parecer lenta lá.

### 3.2 `GET /hmi/config` condicional (corta ~95% do tráfego dos barcos)

A tela busca a config no boot e a cada "atualizar". O payload de 13 KB volta
**inteiro e idêntico** quase sempre. O equipamento já manda o
`config_version` que tem; falta o servidor honrá-lo:

```
GET /api/v1/hmi/config
If-None-Match: "22"            (ou ?known_version=22)

→ 304 Not Modified  (corpo vazio)   quando nada mudou
→ 200 + JSON                        quando mudou
```

Em 4G isso transforma o poll de 13 KB em ~200 bytes. O firmware adota assim
que existir — hoje ele já compara o conteúdo e não remonta nada quando vem
igual, mas o download inteiro acontece mesmo assim.

### 3.3 `config_version` precisa subir em TODA mudança visível

Medido hoje: a **cor de acento** de uma área mudou na plataforma e o
`config_version` continuou `22`. A tela detectou porque compara o conteúdo
byte a byte, mas qualquer cliente que confie na versão (o cache dela existe
para isso) **nunca veria a mudança**. Com o 304 do §3.2 isso vira bug de
verdade: acento mudado jamais chegaria ao barco.

Regra: se o campo sai no `/hmi/config`, mudá-lo sobe a versão.

### 3.4 Assets fora do processo da aplicação

6 KB/s num PNG de 92 KB aponta para o `StaticFiles` servindo do próprio
processo Python. Para produção:

- servir `/uploads` por nginx/CDN (ou ao menos com `Cache-Control` +
  `ETag` — o sha256 já existe no contrato, é o ETag pronto);
- manter o `bytes` correto no manifesto (a tela valida truncamento por ele).

O firmware já só baixa asset quando o sha256 muda, então o custo disso é raro
— mas quando acontece, 16 s de download seguram o "atualizar imagem" inteiro.

## 4. O que a tela já faz (para calibrar o lado de vocês)

| Comportamento | Desde |
|---|---|
| Download de asset só quando o sha256 muda (nunca por força) | 03/08 |
| Config idêntica não remonta a UI (compara conteúdo) | 03/08 |
| Prazos 60 s (dados) / 120 s (imagem), com "ainda baixando..." | 03/08 |
| Uma retentativa automática antes de acusar falha | 03/08 |
| Duração de todo GET no log do equipamento | 03/08 |

## 5. Pendências anteriores que continuam abertas lá

Só para não se perderem (detalhes nos handoffs próprios):

1. `pos_x`/`pos_y` sumiram das três áreas que ganharam `area_kind`
   (HANDOFF-tipos-especiais).
2. Canais de tanque com `unit: "L"` violando o §1.1 do contrato (escala em
   modo tanque deve entregar percentual).
3. Papéis novos a emitir quando existirem: `ai_role: "humidity"`,
   `ai_role: "bilge_level"`, `do_role: "hvac_power"`
   (HANDOFF-climatizacao-bombas §2).
