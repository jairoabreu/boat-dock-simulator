# Handoff — o tempo morto do guincho passou a ser do MÓDULO (I2008IT)

**Data:** 11/08/2026 · **Origem:** cartão #250 (firmware iVS2008, quadro 11) ·
**Para:** tela 10.1" (`matel-ivs-display-p4`, quadro 26), gateway CM06
(`matel-ivs-gateway-fw`) e plataforma web (quadro 29)

Fecha o item 1 — e o único de **segurança** — da análise de múltiplas telas
(#249, `docs/ANALISE-multiplas-telas.md` §3).

## O que estava errado

O intervalo entre inverter o sentido do guincho é guardado **na tela que
acionou**: `ultimo_dir` e `t_parou`, em `screen_ancora.c`. Com duas telas no
barco, a segunda não tem esse estado — `ultimo_dir` vale 0 e **a guarda nem é
avaliada**. Recolhe-se pela tela da proa, solta, e manda-se arriar pela tela do
flybridge no instante seguinte: a inversão sai com o motor ainda girando, dentro
dos 800 ms que o `dead_time_ms` da plataforma existe para proibir.

A `mascara_par` impede os dois sentidos fechados ao mesmo tempo, mas **não
garante intervalo entre eles**, e não havia nada no módulo que segurasse. A
proteção que existia era acidental: a tela que parou insiste no desliga por
~1 s, então o relé **batia** por um segundo antes de ceder.

## O que mudou

**Quem recusa agora é o módulo.** É o único ponto onde os comandos das duas
telas, do CM06 e do aplicativo se encontram, então é lá que a promessa vale para
qualquer número de mestres — inclusive os que ainda não existem.

A guarda está em `digital::set_state()`, o funil por onde passa todo mundo que
fecha um relé, o que inclui o **interruptor de parede** da função de pulso
(#140). Vale para **qualquer par**, não só o guincho: toldo, prancha de popa,
flap.

Está no firmware das duas árvores V5 (a Rust, que é a que vai para campo, e a C,
que é a especificação). **O V4 em campo NÃO tem isto** — ver *O parque antigo*
no fim.

## Configuração — opcode I2008IT = 0x4A

⚠️ **Provisório**, pendente do registro canônico do MTCP, mesma ressalva do
`0x4B`/`0x4C`/`0x4D`/`0x4E`.

| operação  | direção     | DLC | carga                                  |
|-----------|-------------|-----|----------------------------------------|
| escrita   | endereçada  | 5   | `[canal, par, dead_ms u16 LE, 0x5A]`   |
| consulta  | endereçada  | 1   | `[canal]` (`0xFF` = todos)             |
| relatório | **difusão** | 4   | `[canal, par, dead_ms u16 LE]`         |

- `canal` e `par` são 0-based, e só 0–7 são válidos. `par = 0xFF` desfaz.
- `dead_ms` é **milissegundo inteiro** — o mesmo `dead_time_ms` que a plataforma
  já cadastra, sem tradução no caminho.
- O `0x5A` é **trava**, não checksum. Um quadro perdido ou mal endereçado não
  pode desfazer o intertravamento de um guincho.
- **Não há quadro de evento.** A recusa *é* o evento, e ela já tem quadro (o
  I2008NK). Inventar um segundo jeito de dizer não seria dialeto novo.

**O par é simétrico e o módulo o mantém assim.** Gravar `par(2) = 3` grava também
`par(3) = 2`, com o mesmo tempo morto, e **saem dois relatórios**. Um
intertravamento de um lado só é pior que nenhum: protegeria a inversão numa
direção e deixaria a outra passar.

**Leia o relatório, não o que você mandou** — e aqui isso pesa mais que no
I2008IF, porque o número pode voltar diferente:

- **abaixo do piso de 800 ms: aceito e ELEVADO ao piso**, com o relatório dizendo
  o que ficou gravado. Recusar deixaria o par **sem intertravamento nenhum**, que
  é muito pior que 800 ms onde se pediu 500. O 800 é o `ANC_DEAD_MS_PAD` da
  própria tela, mudando de dono;
- **acima do teto de 10 s: recusado.** Isso não é segurança, é erro de digitação
  — um guincho com 30 s de tempo morto parece quebrado ao operador.

**Nasce desligado em todo canal, e o módulo não adivinha par nenhum.** Ele não
tem como saber que a OUT3 e a OUT4 são os dois sentidos de um guincho e não duas
luzes de convés; um par inventado por heurística recusaria comando legítimo de
iluminação, que é o jeito mais rápido de um instalador desligar a segurança
inteira. Quem cadastra `do_role windlass` + `pair_channel` é a plataforma
(migração do #225) — o elo que falta é levar isso ao módulo, ver *O que falta*.

## Recusas (I2008NK, cartão #141) — três motivos novos

| motivo | quando | `detail` |
|---|---|---|
| `TEMPO_MORTO` 0x06 | o par abriu, mas o tempo morto não passou | **quanto falta, em decissegundos**, arredondado para cima |
| `PAR_ENERGIZADO` 0x07 | o outro sentido está fechado agora | o canal do par (0-based) |
| `TEMPO_INVALIDO` 0x08 | escrita de I2008IT acima do teto | o teto, em decissegundos (100) |

Os dois primeiros chegam como recusa de `I2008DS` (`refused_opcode = 0x41`)
endereçada a quem pediu, ou — se a ordem veio de um botão de parede sob a função
de pulso — em **difusão** com `refused_opcode = 0x00` (origem local), exatamente
como o `LIMITE_SIMULTANEAS` já fazia.

Os dois são separados de propósito: em `TEMPO_MORTO` há **um prazo a esperar**,
em `PAR_ENERGIZADO` há **uma condição a desfazer**. O operador precisa saber se
espera ou se desliga o outro sentido primeiro.

## O que a TELA precisa fazer — e é o ponto do handoff

**1. Parar de insistir quando a recusa for `TEMPO_MORTO`.**

Hoje `c6_link.c` reenvia até **5 vezes, a cada 120 ms**, quando o `do_mask` não
confirma. Com o módulo segurando, a troca já é boa: **até 5 quadros de recusa no
lugar de até 5 acionamentos de bobina** — o relé para de bater. Mas dá para
fazer melhor de graça, porque `detail` diz **quanto falta**: ao receber um
`TEMPO_MORTO`, a pendência pode desistir na hora e reagendar para
`detail × 100 ms`, em vez de gastar as cinco tentativas às cegas.

A conta de campo: 5 × 120 ms = 600 ms contra uma janela de 800 ms, então a
rajada inteira cai dentro da janela e é limitada pelo mesmo teto de 5 que
produzia o bate-e-volta. Com duas telas são ~10 quadros a 250 kbit/s. Não é
enxurrada, mas também não é preciso.

**2. Não remover a guarda local da tela.** Ela continua útil: evita o quadro
inteiro quando a própria tela sabe que é cedo, e o parque V4 em campo não tem a
guarda do módulo. O que muda é que ela deixou de ser *a única*.

**3. Mostrar a espera.** Um `TEMPO_MORTO` com `detail = 6` é "aguarde 0,6 s",
não "falhou". Tratar como erro genérico é jogar fora a única informação nova.

## O que falta — o elo do meio, de novo

**O CM06 não tem comando MT2 para o I2008IT**, exatamente como não tinha para o
I2008IF (ver `HANDOFF-funcao-pulso-ivs2008.md`). Hoje a plataforma cadastra
`dead_time_ms` e `pair_channel` e **não tem como levá-los ao módulo**.

A cadeia precisa, nesta ordem:

1. **Gateway CM06** — comando MT2 de escrita e consulta do I2008IT, publicação
   do relatório, e o mapeamento dos três motivos novos para
   `ERR=tempo_morto` / `ERR=par_energizado` / `ERR=tempo_invalido` no
   `ACK`/`EVT` que o `HANDOFF-recusa-comando-mt2.md` já define. **É o bloqueio
   de todo o resto.**
2. **Gateway Go / API** — transporte e persistência do par relatado, e levar o
   `DET=` adiante (item já aberto no handoff de recusa).
3. **Plataforma web** — enviar o par no provisionamento do módulo, junto do
   `do_role windlass` que já existe.
4. **Tela 10.1"** — os três itens da seção acima.

Enquanto o item 1 não existir, **o intertravamento não protege nenhum barco**:
sem configuração, o módulo se comporta exatamente como antes. Isso é
deliberado — o alternativo seria o módulo adivinhar pares — mas significa que
este cartão entrega o *contrato e o mecanismo*, não a proteção em campo.

## Como ver funcionando hoje, sem esperar a cadeia

Direto no barramento, com o `can_tool.py` do repo do firmware:

```sh
python3 tools/can_tool.py set-pair --node 0x41 --channel 2 --pair 3 --dead-time 800
python3 tools/can_tool.py get-pair --node 0x41
python3 tools/can_tool.py set-pair --node 0x41 --channel 2 --pair none
```

Sem hardware nenhum, o emulador e a regressão headless:

```sh
python3.11 tools/intertravamento_sim.py   # 69 conferências, barramento virtual
python3.11 tools/can_node.py              # emulador; REPL aceita `pairs`
```

## ⚠️ Estado da validação — leia antes de prometer data

**NADA DISTO RODOU EM PLACA.** Não havia J-Link nem CM2008_V5 na bancada em
11/08/2026. O que existe:

- `tools/intertravamento_sim.py`, **69 conferências** num barramento virtual,
  emulador e firmware com a mesma lógica. As duas telas são reproduzíveis numa
  bancada de uma porque **as duas assinam `0xFC`** — fixo, ninguém reivindica —,
  então dois quadros de duas telas são, no fio, indistinguíveis de dois da
  mesma. Não é vácua: tirar o braço de tempo morto derruba 7 conferências.
- `bench_interlock()` no `bench.rs`, sete conferências em silício pelo laço
  interno do MCAN — **escrito, compilando, nunca executado**.

Falta, em ordem: rodar o passo em placa; **uma bancada com duas telas e dois
módulos**, que é o que o cartão #250 condiciona explicitamente para ir a barco,
porque o caminho do acionamento é certificado; e um **guincho de verdade**,
porque o que nenhuma simulação alcança é se 800 ms bastam para aquele motor
parar — o número veio da tela, não de medição de inércia.

## O parque antigo (V4, ESP32)

O V4 em campo **não tem** o intertravamento, e os guinchos que estão em barco
hoje estão nesses módulos. O porte é mecânico — a mesma guarda em
`digital::set_state()`, o mesmo registro em NVS no lugar da FRAM — mas
deliberadamente **não** foi feito neste cartão, por três motivos:

1. **Não há como validar.** A bancada não tem adaptador CAN para o V4 (é a mesma
   limitação registrada no handoff da função de pulso), e este é caminho de
   acionamento certificado.
2. **Não protegeria ninguém ainda.** Sem o item 1 da cadeia, nenhum módulo — V4
   ou V5 — recebe configuração de par.
3. **Atualizar V4 de campo é operação própria**, sem OTA, descrita em
   `docs/plano_atualizacao_frota_v4.md`.

Recomendação: **abrir cartão para o V4 depois que o CM06 entregar o item 1**, e
condicioná-lo à mesma bancada de duas telas. Enquanto isso, o barco com duas
telas e um guincho num V4 continua com o defeito, e a guarda local da tela é a
única coisa que existe — o que reforça o item 2 da seção da tela.
