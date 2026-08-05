# Resposta — handoff de desempenho da plataforma

**Data:** 03/08/2026 · **De:** plataforma (`matel-web-platform-api`)
**Para:** firmware da tela 10.1" (`matel-ivs-display-p4`)
**Referência:** `HANDOFF-plataforma-desempenho.md`

> **Resumo em uma linha:** tudo que era código está feito e no dev — 304
> condicional pronto para vocês adotarem, versão que não congela mais, custo
> do 200 cortado, caches nos assets. Duas premissas do handoff estavam
> erradas e valem correção, porque mudam o que vocês fariam a seguir.

---

## 1. O que está pronto no dev (medível já)

| Pedido | Estado |
|---|---|
| §3.2 — GET condicional | ✅ `If-None-Match` → **304 sem corpo** (~250 B). Ver §3 abaixo |
| §3.3 — versão sobe em toda mudança | ✅ consertado — mas a causa não era a que vocês supuseram (§2) |
| §3.4 — assets | ✅ derivadas `hmi/<hash>.png` com `immutable` de 1 ano; e o custo por request sumiu (§4) |
| §5.1 — pos_x/pos_y | ⚠️ **premissa errada** — ver §2 |
| §5.2 — tanque com `unit='L'` | ✅ dados corrigidos + validator 422 + CHECK no banco. Os dois tanques agora servem `%` 3.16–100 / cap 950 L |
| §5.3 — papéis novos (humidity etc.) | ⬜ segue pendente, não entrou nesta rodada |
| §3.1 — produção sem hibernar | ⬜ infraestrutura — decisão do dono do produto |

## 2. Duas correções de premissa

**§5.1 — `pos_x`/`pos_y` NÃO sumiram por causa do `area_kind`.** As três
áreas *nasceram* sem posição: o formulário de criar área nunca enviou
`pos_x`/`pos_y`, e o `/hmi/config` sempre os serviu corretamente. O que
EXISTIA de real (e foi consertado hoje) era o inverso: **arrastar uma área no
Mapa de Bordo apagava o `area_kind`**, porque o PUT era full-replace e o
backend zerava campo omitido. Backend agora trata omitido como "não mexa"
(`exclude_unset`) e o front reenvia o campo. As três áreas ganham posição
sendo arrastadas uma vez — sem risco de perder o tipo.

**§3.3 — o `accent` SEMPRE esteve dentro do hash.** A versão não é contador
por rota: é derivada do conteúdo. O congelamento vinha de uma corrida: dois
GETs sobrepostos (o cold start de 47 s contra o prazo de 30 s de vocês
produzia exatamente isso) liam ambos `(H1, 22)`; um gravava `(H2, 23)` e o
outro `(H3, 23)` por cima. O hash final já era o do conteúdo novo, então
nenhum GET futuro incrementava — **a versão congelava com o conteúdo
andando**. Agora é um UPDATE atômico; a regra "campo que sai no `/hmi/config`
sobe a versão" também virou verdadeira **por construção**: o hash é calculado
sobre o corpo JÁ FILTRADO pelo schema de resposta, não sobre o payload
interno.

## 3. O 304 — o que o firmware precisa fazer

O servidor já responde. Do lado de vocês (`hmi_cloud.c`):

1. Guardar o header **`ETag`** da última resposta 200 na NVS
   (formato `W/"<sha256>"` — guardem a string inteira, opaca).
2. Mandar `If-None-Match: <etag guardado>` em todo GET `/hmi/config`.
3. Tratar **`st == 304`** como "config inalterada": manter cache, estado
   online, **não** remontar UI. Hoje qualquer código ≠ 200 vira falha na tela
   — sem este passo, o 304 apareceria como "Não consegui falar com a
   plataforma" a cada revalidação.

Seguro de adotar já: servidor antigo ignora o header e devolve 200 como
sempre. O ganho é banda (13 KB → ~250 B por poll no 4G), não CPU — o custo
do 200 foi atacado separadamente (§4).

Nota: o `config_version` numérico continua existindo e sobe como antes —
nada muda para a lógica atual de vocês. O ETag é o caminho novo, por cima.

## 4. O cold start e os 6 KB/s — o que explicava

O `api-dev` roda em docker compose num droplet: **não há scale-to-zero**. O
que vocês mediram como "hibernar" era o custo real de cada GET: o servidor
relia o PNG derivado inteiro do disco, refazia o sha256 e reabria com Pillow
**a cada request, dentro do event loop** — com um único worker, uma request
lenta segurava o processo inteiro, e a primeira depois de ocioso pagava tudo
frio (page cache, conexões). Isso foi memoizado e movido para thread; os
20 GETs seguidos que vocês cronometram devem ficar planos agora. Se a
primeira do dia ainda vier lenta em produção, aí sim é infra (keep-warm /
nginx na frente) — está na mesa do dono do produto.

## 5. Pendências que ficaram

- `ai_role: "humidity"`, `"bilge_level"`, `do_role: "hvac_power"` (§5.3) —
  não entraram; avisem a prioridade.
- Editar área existente na UI web (nome/tipo/cor) ainda não existe — só
  criar/excluir/arrastar. Está na fila.
- Produção always-on + nginx/CDN para `/uploads` — infraestrutura.
