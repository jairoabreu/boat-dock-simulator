# Handoff — o elo do meio existe: o CM06 configura a campainha pelo MT2

**Data:** 08/08/2026 · **Origem:** cartão #158 (gateway CM06,
`matel-ivs-gateway-fw`) · **Para:** gateway Go (`matel-gateway`), API
(`matel-api`) e plataforma web (cartão #154, quadro 29)

Resposta a `HANDOFF-campainha-plataforma.md` e a
`HANDOFF-funcao-pulso-ivs2008.md`. **O bloqueio da cadeia saiu.** O CM06 escreve
e consulta o `I2008IF` (0x4E) e publica o relatório do módulo.

Autoridade do formato, e é onde este handoff termina e o contrato começa:
`matel-ivs-gateway-fw/docs/MT2-funcao-campainha.md`.

Estado da cadeia:

| # | onde | estado |
|---|------|--------|
| 1 | CM06 | **feito** (#158) — este documento |
| 2 | Go + API | transporte, persistência e evento ao vivo ← **agora é aqui** |
| 3 | web | ligar o botão da tela ao envio, depois de 2 |

## O que ficou EXATAMENTE como a plataforma pediu

```
escrita:   MT2,<uin>,CMD,<seq>,IF,CH=<0..7>,FN=<0|1>
consulta:  MT2,<uin>,CMD,<seq>,IF?
```

- Destino por UIN, resolvido na injeção.
- O `0x5A` de trava é montado no CM06 e não sobe no MT2.
- `CH ≥ 8` volta `ACK,<seq>,ERR=fora_de_faixa,DET=8`, que a web já traduz — e
  **nada vai ao barramento** nesse caso.
- O `DET` da recusa de origem local (`ORIG=local`) já vinha desde o #145 e segue
  carregando o teto de bobinas **em vigor**, lido do módulo. É o que aposenta o
  `MAX_SAIDAS_SIMULTANEAS` cravado em `apps/nautica/src/lib/api/iot.ts`. Está
  coberto por teste (`nack_cosim.py`, cenário 5).

Um acréscimo que a plataforma não pediu e que vale registrar: `FN` fora de
`0|1` volta `ERR=nao_suportado,DET=0`, decidido no CM06 e sem ir ao barramento.
"Função que não conheço" não pode virar "nenhuma função" — desligar a entrada
por causa de um valor torto seria decidir no lugar de quem pediu.

## O que MUDOU em relação à proposta, e por quê

O relatório **não** é `MT2,<uin>,IF,<mascara_hex>`. É:

```
MT2,<uin>,EVT,<seq>,IF=<mascara_hex>,NODE=<xx>
```

Não é preferência de estilo — a forma proposta **não atravessa o transporte que
existe hoje**, e isso foi conferido no código do `matel-gateway`:

- `internal/protocols/mt2/parse.go` aceita uma lista **fechada** de tipos
  (`IO|CNT|INV|EVT|CMD|ACK`). `IF` vira `ErrUnknownKind`, e a linha não é apenas
  descartada: ela cai em `PublishRawFrame(…, "mt2-invalido")` **e** em
  `RecordUnknownDevice`. O relatório de cada escrita viraria ruído de
  "equipamento desconhecido" em Ferramentas > Administrativo.
- Um `<mascara_hex>` posicional cairia no lugar do `seq`, que é campo de
  gramática (`MT2,<uin>,<tipo>,<seq>,<campos K=V>`), não campo livre.

É a mesma armadilha que fez a recusa nascer como `ERR=` em vez de um tipo
`NACK` (#145). Como `EVT` com a máscara em `K=V`, a linha atravessa o parser de
**hoje**: `handleEvent` a reconhece como evento sem consumidor e a publica no
stream de raw frames — o mesmo caminho por onde `io-refusal.ts` já lê a recusa
local. Ou seja, **a web pode começar a consumir agora**, pelo caminho torto que
ela já usa, sem esperar o item 2.

### O que isso pede do item 2 (Go + API)

1. Uma projeção `IF()` em `internal/protocols/mt2/parse.go`, análoga a `CNT()`:
   `EVT` **com campo `IF=`** é relatório de configuração, `EVT` com `NACK=` é
   recusa. `RecusaDoEvento()` já devolve `false` sem `NACK=`, então nada
   existente muda de comportamento — é só somar um ramo em `handleEvent`.
2. Persistir **por UIN**, nunca por `node_id`, e guardar o instante do
   relatório junto: é o `lido_em` que a web usa para decidir se a resposta ainda
   vale (`VALIDADE_RELATORIO_MS`). O `NODE=` do payload é informativo, igual ao
   do `MT2,IO`.
3. `GET .../io/campainha` com cache velho dispara a **consulta** no barramento
   (`IF?`) e responde o que tiver. O CM06 já trata a consulta como comando
   normal: `ACK,OK` na hora e o relatório logo em seguida, em mensagem separada.
4. O `PUT` responde `202` e o desfecho vem pelo `command_result` que já existe.
   **O estado novo vem do relatório**, não da resposta do PUT.

## A regra que o firmware faz questão de sustentar

**O relatório é a única fonte do estado, e o CM06 não guarda cópia da máscara.**
Ela vale no instante do relatório e é publicada na hora. Guardar uma repetiria o
cache de UIN do #156: um valor que o barramento não confirmou, pronto para ser
atribuído à placa errada depois de uma troca no mesmo endereço.

Consequência prática, e ela está sob teste: se alguém configurar o módulo **por
fora** do MT2 (o `can_tool.py` do instalador na bancada), a consulta seguinte
traz a verdade nova. Uma nuvem que derivasse a máscara do que mandou mostraria
o valor antigo e estaria errada.

⚠️ E `ACK,OK` continua significando "ninguém recusou", **não** "está gravado":
módulo antigo nunca emite `I2008NK`. Quem afirma a configuração é o relatório,
como o `do_mask` é quem encerra um acionamento.

## Como ver funcionando, sem hardware

```bash
cd matel-ivs-gateway-fw/tools/cosim && make && python3.11 campainha_cosim.py
```

24 conferências entre o emulador real do módulo (`~/CM2008/tools/can_node.py`) e
o firmware real do CM06 compilado para o hospedeiro, num barramento CAN virtual.
Cobre ligar e desligar pelo MT2, o toque na parede invertendo o relé nos dois
sentidos, a consulta repetindo o relatório, a configuração mexida por fora
aparecendo na consulta seguinte, as recusas locais sem nada sair no barramento,
e o `0x5A` conferido no quadro CAN cru.

## Pendências que NÃO são deste cartão

- **Severidade no catálogo de eventos** (item 4 do handoff da plataforma): com a
  função ligada, o `do_mask` muda sem comando nenhum. O CM06 já trata assim — a
  telemetria é on-change e não correlaciona com comando pendente. Quem ainda
  precisa concordar é o backend: um evento de saída que nasça com severidade
  `alarm` enche a caixa do cliente toda vez que acenderem a luz do salão.
- **Evento de primeira classe no WS** (`kind: "io_event"`): segue valendo o
  pedido do handoff da plataforma. O CM06 já entrega tudo decomposto no payload;
  falta o item 2 parar de exigir que a web leia `raw_frame`.
