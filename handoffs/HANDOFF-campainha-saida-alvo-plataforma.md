# Handoff — a saída-alvo da campainha já existe na plataforma: o que falta é o MT2

**Data:** 26/08/2026 · **Origem:** cartão #283 (plataforma web, quadro 29) ·
**Para:** gateway CM06 (`matel-ivs-gateway-fw`, cartão #282), gateway Go
(`matel-gateway`) e o contexto do iVS2008 (cartão #281)

Resposta à revisão de hoje do `HANDOFF-funcao-pulso-ivs2008.md` (#281), que
tirou o par posicional do firmware. A plataforma fez a metade dela: o
interruptor de campainha virou TIPO de entrada, a saída passou a ser escolha do
instalador, e a escolha existe no banco, na API e na tela. **O que não existe é
o campo no fio** — e este documento diz exatamente o que a web já sabe mandar,
para o #282 não precisar adivinhar a forma.

## O que já está de pé (dev, 26/08/2026)

| onde | o quê |
|---|---|
| banco | `io_channels.di_role='bell_switch'` + `bell_out_channel` (migração 098) |
| porteiro | a campainha reivindica DOIS bornes — a entrada e a saída ESCOLHIDA |
| API | `PUT .../io/campainha/{ch}` aceita `out_channel`; o espelho publica a capacidade |
| web | seletor de tipo + seletor de saída filtrado, com o porquê de cada recusa |

Nulo é o PAR POSICIONAL em toda essa cadeia, e nunca "nenhuma saída": é o que a
placa faz desde o #140 e o que todo cadastro anterior significa.

## A linha que a plataforma manda

```
escrita:   MT2,<uin>,CMD,<seq>,IF,CH=<0..7>,FN=<0|1>[,OUT=<0..7>]
consulta:  MT2,<uin>,CMD,<seq>,IF?
```

`OUT=` só aparece quando a saída DESVIA do par. Duas razões, e nenhuma é
preguiça:

* o parque instalado continua recebendo a linha que ele já atravessa inteira —
  estrear um campo desconhecido em todo módulo, para dizer o que ele já faz,
  seria pedir uma recusa de graça;
* o `OUT=` vai como campo `K=V` e não posicional, que é a gramática que o
  parser do gateway atravessa (`MT2,<uin>,<tipo>,<seq>,<campos K=V>`). É a
  mesma lição que fez o relatório nascer `EVT ... IF=` em vez de um tipo `IF`
  próprio (#158): a forma "natural" não passava pelo transporte que existe.

Se o #282 escolher outro nome ou outra posição, é UMA função que muda na web
(`_mt2_campainha`, em `matel/routers/iot.py`) — mas diga qual, porque hoje ela
está escrita assim e coberta por teste.

## O que a plataforma precisa DE VOLTA

### 1. O relatório com o par, não com a máscara

A revisão do #281 diz que o espelho "deixa de ser uma máscara de 8 bits e passa
a ser uma lista de pares", e que o `enabled_mask` não existe mais no fio. A web
concorda e **ainda lê a máscara**, porque é o que o MT2 carrega hoje
(`MT2,<uin>,EVT,<seq>,IF=<mascara_hex>,NODE=<xx>`). Enquanto for assim, a nuvem
sabe QUAIS entradas são campainha e não sabe o que cada uma aciona — ela assume
o posicional, que é a única leitura honesta de uma máscara.

O que se pede é o relatório carregando o alvo, na mesma gramática:

```
MT2,<uin>,EVT,<seq>,IF=<canal>,FN=<0|1>,OUT=<0..7>,NODE=<xx>
```

…ou a forma que o #282 achar melhor, desde que **um relatório nomeie uma
entrada e o alvo dela**. É o que fecha a conferência que o #283 abriu: a nuvem
guarda a INTENÇÃO (o cadastro), a placa afirma o que está gravado, e a tela
mostra a divergência em vez de escolher um dos dois para acreditar. Com a
máscara, a divergência de ALVO é invisível.

E vale o que o #281 já garantiu e a web depende: **o relatório traz o alvo mesmo
com `FN=0`**. Desligar não apaga o alvo, e é isso que deixa a tela reabrir
mostrando o que aquele botão acionava.

### 2. A capacidade — como saber que este módulo aceita `OUT=`

Este é o buraco que sobrou, e é o único que impede a função de ir ao ar.

A plataforma NÃO tem a versão de firmware de módulo nenhum. `devices.model`
carrega a geração (`ivs2008-v4`/`v5`) e nada mais; o UIN não carrega versão
(`ARQUITETURA-uin-v2.md`). Então hoje `saida_livre_no_modulo()` responde **não**
para o parque inteiro, e a tela trava o seletor no par posicional com a
explicação — inclusive nas placas que já rodam o firmware do #281.

Não é conservadorismo: mandar `OUT=` para um firmware que o ignora é o pior
desfecho possível, porque a placa acende o relé do par assim mesmo e a tela
mostra outra luz. Melhor travar e explicar.

O que resolve, em ordem de preferência:

1. **o INV/inventário declarando o que o módulo sabe fazer** — uma capacidade
   nomeada (`if_out`, por exemplo) vale mais que uma versão, porque a
   plataforma não deveria manter uma tabela de "da versão X para cima";
2. **a versão do firmware do módulo em algum relatório**, e a plataforma faz a
   tabela;
3. **o CM06 recusando `OUT=` com um código próprio** quando o módulo não sabe.
   Serve, mas é o pior dos três: o instalador só descobre depois de tentar.

Quando existir, o que muda na web é o corpo de UMA função —
`saida_livre_no_modulo()`, em `matel/services/io_campainha.py`. A tela, a rota e
o cadastro já perguntam a ela.

### 3. Duas entradas na mesma saída: a plataforma aceitou

O #281 pediu que a tela não tratasse o interruptor paralelo como conflito. Está
feito nos dois lados: a matriz do porteiro ganhou `CAMPAINHA_RELE` consigo
mesmo (`services/io_portas.py`) e o seletor mostra "também acionada pela DI5"
em vez de desabilitar a opção.

Fica registrado que isso EMENDA a Fase 0 do #268, fechada em 21/08 — a ata de
lá diz "campainha exige saída genérica livre". Ela fechou sem esse caso porque
o par posicional o tornava inexprimível, não porque alguém o tenha recusado.

### 4. A entrada 9 em diante

O #281 diz que a limitação "virou de formato, não de hardware". A plataforma
continua recusando campainha de DI8 para cima, porque é o que o fio aceita hoje
(`CH=<0..7>`). Quando o formato abrir, é uma constante — `CANAIS_COM_PAR` — e
ela já mora num lugar só nos dois repos.

## Onde isto está, do lado da web

* `matel/services/io_campainha.py` — a régua do alvo e a capacidade;
* `matel/services/io_portas.py` — a matriz, com a emenda do paralelo;
* `matel/routers/iot.py` — `_mt2_campainha`, o porteiro e a importação;
* `alembic/versions/098_campainha_saida_alvo.py`;
* `apps/nautica/src/lib/api/io-campainha.ts` — a régua do seletor, espelhada;
* testes: `tests/test_campainha_alvo.py` (API) e
  `apps/nautica/tests/io-campainha-alvo.test.ts` (web).

## E o parque que já tem a função ligada

`POST /devices/{id}/io/campainha/importar` traz para o cadastro as campainhas
que o módulo já relata. É rota e não backfill de migração de propósito: a
configuração que vale é a da PLACA, e inventá-la no banco gravaria um palpite
sobre módulos que podem ter sido reconfigurados pelo `can_tool.py` da bancada.
Ela importa o alvo POSICIONAL porque é o que a máscara sabe dizer — quando o
item 1 existir, ela importa o par de verdade.
