# Handoff — MTCP `0x52`: RECONHECIMENTO DE ALARME em broadcast entre painéis

**Data:** 11/08/2026
**De:** firmware da tela 10.1" de automação (`matel-ivs-display-p4`)
**Para:** gateway CM06 (`matel-ivs-gateway-fw`), firmware do iVS2008 (`~/CM2008`)
e quem mais escrever um painel no MTCP
**Cartão:** #252 (quadro 26) — item 2 da ordem recomendada de
`matel-ivs-display-p4/docs/ANALISE-multiplas-telas.md` §4 (cartão #249)

> **Resumo em uma linha:** nasce o opcode `0x52` — a tela que RECONHECE um
> alarme anuncia no fio, e todo painel que ouvir marca o MESMO alarme como visto
> e cala o bip. Um quadro por alarme, identidade estável (tipo + UIN do nó +
> canal), idempotente, sem resposta e sem estado no fio.
>
> **Mudança necessária no CM06 e no iVS2008: nenhuma.** O `0x52` é registrado
> nos dois para o número não ser reaproveitado; ignorá-lo é o comportamento
> correto de hoje. O §7 diz o que o CM06 ganharia se um dia quiser ouvi-lo.

---

## 0. O problema, na queixa de quem usa

Por decisão da demanda #198, na tela de automação **quem cala o bip é ABRIR a
página de alarmes** — não há botão SILENCIAR, porque ter a lista na frente do
operador É o reconhecimento. Isso resolve com UMA tela.

Com duas, abrir a página na tela do salão marca "visto" só na tela do salão. **A
do flybridge continua piscando o sino e bipando** depois de o alarme já ter sido
atendido, e alguém tem de subir lá para calá-la. Na `INUNDAÇÃO` é pior: o
operador está com as mãos no problema e o painel do outro convés continua
gritando por um alarme que já foi visto, entendido e está sendo resolvido.

É informação **de painel**, não de módulo: nenhum iVS2008 tem opinião sobre
quem olhou para a tela. Por isso o `0x52` é irmão do `0x50`/`0x51`
(`HOST_STATUS`/`HOST_PING` do CM06) — a faixa `0x50+` do MTCP é dos cidadãos do
barramento que não são módulo.

---

## 1. O quadro

CAN estendido, 250 kbit/s, `ID = (prio<<24) | (destiny<<16) | (source<<8) | cmd`.

| campo | valor |
|---|---|
| `cmd` | **`0x52`** (`MTCP_CMD_PANEL_ALM_ACK`) |
| `source` | `0xFC` — PAINEL. É o nome das duas telas; ver §4 |
| `destiny` | `0xFF` — broadcast |
| `prio` | `0x03` (`MTCP_PRIO_HIGH`, o mesmo de toda a emissão do painel) |
| `DLC` | **8**, sempre |

```
[0]    versão(4 bits altos) | escopo(4 bits baixos)
       versão = 0 hoje. Quadro com versão desconhecida é DESCARTADO INTEIRO.
       escopo = 0 = "reconheci ESTE alarme". Não há outro escopo — ver §3.
[1]    tipo do alarme (a tabela ALM_* do §2)
[2]    canal, 0-based; 0xFF = a condição não é de um canal (é do barco)
[3]    endereço do nó, 0x41..0x4F; 0x00 = a condição não é de um módulo
[4..6] VERIFICADOR: 24 bits BAIXOS do UIN do nó, LE. 0 = o emissor não conhecia
       o UIN daquele endereço
[7]    painel que reconheceu — byte de DIAGNÓSTICO (§4)
```

**Quem manda:** só um painel, e só no gesto de reconhecimento (abrir a página de
alarmes, ou a vigília que a abre sozinha). Não é periódico, não tem resposta,
não tem retransmissão e não tem heartbeat. Um barco com duas telas e um alarme
põe **um quadro por alarme reconhecido** no fio, e depois silêncio.

**Single-shot obrigatório** (`m.ss = 1`): sem isso, um quadro sem ACK — tela
sozinha na bancada — é retransmitido para sempre pelo controlador e entope a
fila de TX das escritas de carga. É a mesma disciplina do `cm_write_output`
(incidente de 01/08/2026).

---

## 2. A IDENTIDADE do alarme: tipo + UIN + canal, nunca índice

O erro fácil aqui seria mandar "reconheci o alarme número 3". **O número 3 é
posição no vetor de uma tela** — o livro-caixa de cada painel cresce na ordem em
que ELE viu as condições subirem, e a tela que bootou depois tem outra ordem. O
alarme 3 de uma é o 1 da outra.

A identidade que viaja é a mesma que o livro-caixa usa para achar um registro:

- **tipo** — `ALM_*`, tabela abaixo, congelada por este contrato;
- **nó** — por **UIN**, com o endereço só como transporte
  (`HANDOFF-vinculo-uin.md`): o endereço `0x41..0x4F` é derivado do serial e
  renegociado a cada entrada no barramento, então ele sozinho não identifica
  ninguém;
- **canal** — 0-based, do jeito que a config da plataforma numera.

| `tipo` | significado |
|---|---|
| 0 | `INUNDAÇÃO` (boia de água alta) |
| 1 | `INFILTRAÇÃO` (critério de horímetro da bomba de porão) |
| 2 | `TANQUE BAIXO` |
| 3 | `TANQUE CHEIO` |
| 4 | `TEMPERATURA BAIXA` |
| 5 | `TEMPERATURA ALTA` |
| 6 | `SEM COMUNICAÇÃO` (nó `0x00`, canal `0xFF`) |
| 7 | `REDE CAN EM QUARENTENA` (nó `0x00`, canal `0xFF`) |
| 8 | `TENSÃO DE BATERIA BAIXA` |
| 9 | `SOBRETENSÃO NA BATERIA` |

**Tipo desconhecido é ignorado, não é adivinhado.** Um painel mais novo que
invente o tipo 10 não cala nada num painel mais velho — que é o lado seguro do
erro: o pior que acontece é o bip continuar.

### 2.1 Por que o UIN vai TRUNCADO, e por que isso não é preguiça

O UIN é `AAMMDDSSSS` em u64 e não cabe num quadro que também precisa carregar
tipo, canal e origem. Duas saídas ruins seriam mandar só o endereço (identidade
que muda sozinha) ou partir o reconhecimento em dois quadros (estado no fio).

A saída é: **o endereço resolve, o UIN CONFERE.** O receptor já tem a mesma
tabela viva UIN↔endereço que o emissor — os dois ouviram os mesmos
`ADDR_CLAIM`/`ADDR_ANNOUNCE`. Então o quadro manda o endereço, e os 24 bits
baixos do UIN provam que os dois lados estão falando do mesmo módulo.

Regra de aceitação, escrita para não sobrar dúvida:

| verificador do quadro | UIN que o receptor tem para aquele endereço | decisão |
|---|---|---|
| bate | conhecido | **aceita** |
| não bate | conhecido | **DESCARTA** e loga: as tabelas discordam, alguém está com um endereço velho |
| `0` (emissor não sabia) | qualquer | **aceita**, com log |
| qualquer | desconhecido (receptor nunca ouviu o claim) | **aceita**, com log |

Colisão de dois módulos do mesmo barco nos 24 bits baixos do UIN é ~1 em 16
milhões, e o preço dela é um bip calado a mais — não é um comando no relé
errado. É por isso que 24 bits bastam **como verificador** e não bastariam como
identidade.

---

## 3. As três decisões que este contrato fecha

### (a) Vale para alarme que a outra tela ainda NEM VIU subir? **NÃO.**

O reconhecimento marca visto **só o que está ATIVO no receptor no instante em
que o quadro chega**. Um alarme que subir depois nasce não-visto, pisca e bipa.

É a mesma regra que já vale dentro de uma tela: uma subida nova (ou a repetição
por `cooldown_min`) sempre limpa o "visto", porque é ocorrência NOVA e
reconhecer a anterior não reconhece esta. Reconhecimento é um ato sobre o que
foi mostrado a alguém; ele não pode valer para o futuro.

É também por isso que **não existe escopo "reconheci tudo"**. Um quadro só
diria "marque visto tudo que estiver ativo aí" — e calaria no outro painel uma
condição que ele enxerga e o emissor não (canal que só um dos dois estava
observando, tela que subiu antes e viu o transitório). Um quadro por alarme
custa alguns bytes e não mente.

### (b) LIMPAR HISTÓRICO também é broadcast? **NÃO — fica LOCAL.**

Três motivos, e o terceiro decide sozinho:

1. O histórico é, por definição da #198, *"o que ESSA TELA acusou"*. As dez
   linhas divergem entre os painéis conforme cada um esteve ligado, e isso não é
   defeito: são duas testemunhas.
2. Limpar é **destrutivo e não-idempotente** — o oposto exato do `0x52`. Um
   quadro perdido no reconhecimento não custa nada; um quadro de limpeza
   duplicado ou atrasado apaga evidência que ninguém mandou apagar.
3. `alarmes_limpar_passados()` também derruba os **ativos SEM LEITURA**. Uma
   condição pode estar sem leitura numa tela e sob leitura na outra. Um broadcast
   de limpeza apagaria, no painel B, um alarme que B está observando agora.

Fica registrado aqui para que ninguém adicione depois por simetria: **limpeza
não viaja.**

### (c) Tela que estava desligada e sobe depois: pergunta, ou nasce não-vista?

**Nasce não-vista.** Não há quadro de consulta e não há repetição do
reconhecimento.

Quem chegou agora não atendeu nada — o barco não deve a ele o silêncio. E o
custo do erro é do lado certo: uma tela que sobe no meio de uma inundação já
reconhecida vai piscar e bipar até alguém olhar para ela, o que é exatamente o
que se quer que aconteça com uma tela que ninguém sabe se está sendo olhada.

O contrário — a tela nova perguntar "o que já foi reconhecido?" — exigiria
resposta, estado e um dono para responder. Caro, e para comprar silêncio.

---

## 4. Quem reconheceu, e por que esse byte NÃO decide nada

As duas telas assinam `source = 0xFC`. Isso é decisão antiga e continua certa
(nenhuma tela reivindica endereço; ver `ANALISE-multiplas-telas.md` §1), mas
significa que o `source` não distingue os painéis.

O byte `[7]` é o **id de painel**: o último byte do MAC de fábrica do P4. Ele
serve para o log dizer *"reconhecido no painel 3F"* em vez de *"reconhecido em
algum lugar"*, que é a diferença entre diagnosticar e adivinhar num barco com
dois conveses.

**Ele não é usado para nenhuma decisão**, e o contrato proíbe que passe a ser:
são 8 bits, dois painéis colidem com 1/256 de chance, e um id colidido não pode
virar comando calado. `0x00` = painel que não conseguiu ler o próprio MAC — e
`0x00` é um id como outro qualquer, só menos informativo no log.

O painel **não recebe o próprio quadro** (o TWAI não faz auto-recepção fora do
modo de teste), então não há eco para filtrar. Se um dia houver, a idempotência
já cobre: reconhecer o que já está reconhecido não faz nada.

---

## 5. Quadro perdido, repetido, atrasado

O `0x52` é **idempotente e sem memória**:

- **Perdido** — o alarme continua não-visto naquele painel: ele pisca e bipa até
  alguém abrir a página lá. Nada trava, nada fica inconsistente, e o operador
  tem o mesmo trabalho que tinha antes deste contrato existir. **Não há
  retransmissão de propósito**: repetir um "eu vi" que se perdeu vale menos que
  o tráfego, e um alarme que ninguém calou é um alarme que continua avisando.
- **Repetido** — a segunda vez não faz nada. O receptor só age sobre registro
  ATIVO e AINDA NÃO VISTO.
- **Atrasado** (chegou depois de a condição normalizar) — não acha registro
  ativo, não faz nada. E se a condição SUBIU DE NOVO nesse meio tempo, o alarme
  já é ocorrência nova: o quadro velho não a cala, porque a regra do §3(a) é
  sobre o instante da chegada, não sobre o instante da emissão.

Nenhum desses casos precisa de fila, de sequência ou de ACK. É por isso que o
`0x52` não tem nada disso.

---

## 6. Rajada: o teto, e para que lado ele erra

Um gesto de reconhecimento pode cobrir vários alarmes ao mesmo tempo. A tela
emite **no máximo 8 quadros por gesto** e loga quantos ficaram de fora.

O teto existe porque a emissão sai do contexto do LVGL (é o mesmo caminho do
toque que aciona carga), e 40 `twai_transmit` em fila roubariam o toque — o
pecado capital deste firmware. O erro cai para o lado seguro: **o excedente
segue NÃO-VISTO no outro painel**, que continua avisando. Nunca o contrário.

Oito cobre com folga o barco real: reconhecer 9 alarmes distintos de uma vez é
um casco em situação em que ninguém está contando bips.

---

## 7. O que muda no CM06 e no iVS2008: nada, e o número está reservado

Registrar o `0x52` nos dois repos é o pedido inteiro — do mesmo jeito que o
`0x50`/`0x51` foram registrados aqui na tela mesmo sem ela emiti-los. O
`can_mtcp.h` do CM06 recebe o `#define` e este bloco de contrato; o decode não
precisa de linha nenhuma, porque **ignorar é o comportamento correto**: o CM06
não tem página de alarmes e não tem operador na frente.

> ⚠️ Como o `0x4B`/`0x4C`/`0x4D`/`0x4E`, o **`0x52` é PROVISÓRIO**: o registro
> canônico do MTCP não estava acessível quando isto entrou. Se ele mudar, muda
> nos dois `can_mtcp.h` ao mesmo tempo.

O que o CM06 ganharia se um dia quisesse ouvir (fora de escopo hoje, anotado
para não se perder):

- **publicar o reconhecimento na nuvem** — "alarme X reconhecido a bordo às
  03:12" é a informação que falta hoje no app: ele sabe que o alarme subiu e não
  sabe se alguém olhou;
- **calar a notificação push** de um alarme que a tripulação já atendeu, que é
  a mesma queixa deste handoff, um nível acima.

Nenhuma das duas muda o quadro. Se forem feitas, são consumo puro.

---

## 8. Onde está, do nosso lado

| Arquivo | O quê |
|---|---|
| `main/can_mtcp.h` | `MTCP_CMD_PANEL_ALM_ACK`, o layout e a API (`cm_alm_ack_tx`, `cm_alm_ack_cb`, `cm_painel_id`) |
| `main/can_mtcp.c` | `on_alm_ack` (RX, com a conferência do verificador) e `cm_alm_ack_tx` (TX single-shot) |
| `main/alarmes.c` | `alarmes_marcar_vistos` passou a anunciar; a fila que traz o reconhecimento da task de RX para o contexto LVGL; `ack_aplica` |
| `matel-ivs-gateway-fw/main/can_mtcp.h` | o mesmo `#define` e este contrato em resumo (o CM06 ignora) |

**Bancada:** provado com UMA tela por cossimulação (injeção do quadro no
`on_frame`, os dois sentidos). **Falta bancada com DUAS telas 10.1" no mesmo
barramento** — é o único jeito de provar a ponta a ponta, e o cartão #252 diz
que não vai a barco sem ela.
