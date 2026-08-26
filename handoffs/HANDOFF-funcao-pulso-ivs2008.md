# Handoff — função de pulso do iVS2008: interruptor de campainha aciona o relé

**Data:** 08/08/2026 · **Origem:** cartão #140 (firmware iVS2008, quadro 11) ·
**Para:** plataforma web (quadro 29) e gateway CM06 (`matel-ivs-gateway-fw`)

> **Revisão de 26/08/2026 — cartão #281.** O par deixou de ser posicional: o
> instalador escolhe **qual saída** a entrada aciona. Isso muda a escrita, muda
> o relatório e acrescenta uma recusa. O formato está fechado na seção
> *Configuração* abaixo, e a de compatibilidade diz o que continua valendo para
> quem já fala a versão antiga. Quem já leu este handoff: releia a partir de
> *Configuração*; o resto (por que existe, o que a tela precisa saber) segue
> valendo palavra por palavra.

O módulo ganhou uma função nova: **uma entrada acionada por pulso inverte o relé
que faz par com ela**. Aperta o botão da IN1, a OUT1 muda de estado; aperta de
novo, volta. É o que faz um interruptor de campainha (botão de toque, sem
retenção) comandar uma luz — a instalação padrão de embarcação de alto padrão.

Está no firmware das três árvores (V4 em campo, V5 de referência, V5-rs) e
validado em placa. **Nasce desligada em todo canal** e só liga por configuração
explícita, que fica gravada no módulo.

Este handoff existe porque a ativação tem de chegar ao instalador pela
plataforma, e hoje **não chega**: falta o elo do meio. Ver *O que falta* abaixo.

## O que a função faz, em uma tela

- O par é **escolhido pelo instalador** desde o cartão #281: a entrada IN(N)
  aciona a saída que estiver gravada no módulo para ela, e não obrigatoriamente
  a OUT(N). O padrão de fábrica continua sendo o posicional IN(N)→OUT(N), e um
  módulo nunca configurado se comporta como antes. As entradas de IN9 para cima
  **ainda não aceitam a função** — a limitação virou de formato, não de
  hardware; ver *Compatibilidade e limites* abaixo.
- Duas entradas **podem** apontar para a mesma saída, e isso é de propósito:
  é o interruptor paralelo de escada (botão no camarote e botão no salão
  comandando a mesma luz). Diferente do intertravamento I2008IT, este par
  **não é simétrico** e o módulo nunca escreve nada num canal que a escrita não
  nomeou.
- A inversão lê o **estado vivo do relé**, não uma sombra interna. Uma luz
  acesa pela plataforma e apagada no botão da parede concordam depois. É a
  instalação para a qual isto existe.
- O estado das saídas **não sobrevive a uma queda de energia**. O relé não é
  latching; faltou energia, tudo volta para o repouso, que é o safe-state do
  produto. Consequência para o operador: depois de um piscar de luz, aperta de
  novo. Não prometa restauração na interface.
- Funciona **sem barramento**. Fiação local: um módulo sem endereço, ou num
  barramento sem mais ninguém, continua atendendo o interruptor de parede.
- Um toque pode ser **recusado** pelo teto de 6 bobinas simultâneas. Quando é,
  o módulo diz no barramento (ver *Recusas*).

## Configuração — opcode I2008IF = 0x4E

⚠️ **Provisório**, pendente do registro canônico do MTCP (o `MTCP.ods` continua
fora da máquina de desenvolvimento). Mesma ressalva do horímetro `0x4D`.

**Formato fechado em 26/08/2026 pelo cartão #281.** Quatro quadros dividem o
opcode, distinguidos pelo DLC — a mesma convenção que o I2008AL e o I2008IT já
usam, e que aqui já separava consulta de escrita:

| operação          | direção     | DLC | carga                          |
|-------------------|-------------|-----|--------------------------------|
| escrita           | endereçada  | 4   | `[canal, função, alvo, 0x5A]`  |
| escrita (legada)  | endereçada  | 3   | `[canal, função, 0x5A]`        |
| consulta          | endereçada  | 1   | `[canal]` (`0xFF` = todos)     |
| relatório         | **difusão** | 3   | `[canal, função, alvo]`        |

- `canal` é a **entrada**, 0-based, e só 0–7 são válidos.
- `função`: `0` = nenhuma, `1` = inverter a saída-alvo.
- `alvo` é a **saída**, 0-based, 0–7. O valor `0xFF` na escrita quer dizer
  "posicional": o módulo resolve para o próprio `canal` e **relata o número
  resolvido**, nunca o `0xFF`. É o mesmo princípio do tempo morto do I2008IT
  que sobe ao piso — quem configurou tem de ver com o que o módulo ficou.
- O `0x5A` é **trava**, não checksum. Não é sobre perder dado — a configuração é
  reversível — é sobre um quadro perdido ou mal endereçado fazer um relé passar
  a se mover sozinho quando uma boia de porão fecha. Ele é sempre o **último**
  byte da escrita, e é isso que deixa o DLC distinguir as duas versões sem
  ambiguidade: `0x5A` no índice 2 é escrita legada, no índice 3 é escrita com
  alvo.
- O relatório sai **a cada escrita aceita e a cada consulta**, nunca
  periodicamente. É **um quadro por canal**: uma escrita aceita produz **um**
  relatório (o canal escrito — este par não é simétrico e nada mais se moveu),
  uma consulta de canal produz um, e uma consulta `0xFF` produz **oito**.
- O relatório carrega o alvo **mesmo com `função = 0`**. Desligar não apaga o
  alvo gravado, e o relatório sempre diz os dois campos: assim a tela mostra
  para o eletricista a fiação conferida mesmo com a função desarmada.

**Leia o relatório, não o que você mandou.** O módulo é o dono da configuração:
ela vive na memória não-volátil dele (NVS `PULSE` no V4, registro FRAM no V5) e
sobrevive a troca de firmware e a mudança de endereço CAN. Uma cópia na nuvem é
cache, e cache que ninguém revalida é como a plataforma acaba mostrando uma
função ligada num módulo que foi trocado.

### Compatibilidade e limites

- **Ferramenta velha continua funcionando.** Uma escrita DLC 3 (sem o byte de
  alvo) é aceita e grava o alvo **posicional** — `alvo := canal`. Não é um modo
  de compatibilidade preguiçoso: é a regra literal, sempre, mesmo que aquele
  canal já tivesse um alvo escolhido. Uma ferramenta que não sabe do alvo não
  pode preservá-lo sem saber que ele existe, então ela o **reescreve para o
  padrão** — e o relatório diz isso na hora. Quem quiser preservar, mande DLC 4.
- **Relatório mudou e isso quebra leitor antigo, de propósito.** O relatório
  DLC 2 `[seletor, máscara]` **não existe mais**; não há emissão dupla. Manter
  os dois seria duas fontes de verdade sobre a mesma coisa, que é exatamente
  como o #257 fez a plataforma publicar uma configuração que não existia mais.
  Hoje o único leitor do relatório é o `can_tool.py` deste repo — o CM06 ainda
  não tem caminho para o I2008IF (ver *O que falta*), então a quebra não alcança
  a frota. **Quem implementar o lado CM06 já implementa a versão nova.**
- **Uma consulta antiga vira consulta de tudo.** A ferramenta velha manda DLC 1
  com `0xFF` no byte, que o firmware antigo ignorava; no formato novo esse
  mesmo `0xFF` quer dizer "todos os canais". A intenção sobreviveu por acidente
  feliz, e ficou registrada aqui para ninguém a "consertar" depois.
- **Entradas seguem 0–7.** IN9..IN16 do V5 continuam sem aceitar a função. O
  motivo mudou: antes era físico (não havia relé para fazer par), agora é de
  formato — a máscara interna e o campo `canal` do relatório foram dimensionados
  para oito. Estender para 16 entradas é decisão de produto separada e **não
  foi feita** no #281; custa um cartão novo e mexe em CM06 e plataforma junto.
- **FRAM.** O registro `PULSE` do V5 passou a versão 2 e guarda o alvo por
  entrada. Um módulo que já estava em campo com o registro versão 1 é **migrado
  na leitura** para alvos posicionais, que é exatamente o comportamento que ele
  tinha — a migração é gravada na próxima escrita aceita, não no boot. Ninguém
  perde configuração e nenhum relé se move por causa da atualização.

## Recusas (I2008NK, cartão #141)

Chegam desta função:

| motivo                     | quando                                          | `detail`           |
|----------------------------|-------------------------------------------------|--------------------|
| `FORA_DE_FAIXA` 0x02       | escrita numa **entrada** ≥ 8                    | nº de entradas (8) |
| `SAIDA_INVALIDA` 0x09      | escrita com **alvo** ≥ 8 (e ≠ `0xFF`)           | nº de saídas (8)   |
| `NAO_SUPORTADO` 0x03       | valor de `função` que o firmware não conhece    | 0                  |
| `LIMITE_SIMULTANEAS` 0x01  | **toque recusado**: passaria do teto de bobinas | teto em vigor (8)  |
| `TEMPO_MORTO` 0x06         | **toque recusado**: o par inverteria cedo demais | ds que faltam     |
| `PAR_ENERGIZADO` 0x07      | **toque recusado**: o outro lado do par está ligado | canal do par   |

`SAIDA_INVALIDA` **é motivo novo, do cartão #281** — não é `FORA_DE_FAIXA`
reaproveitado, e a diferença não é cosmética: uma escrita pode errar a entrada
ou errar a saída, e os dois casos mandam o instalador corrigir campos
diferentes do formulário. Reaproveitar o 0x02 traria de volta exatamente o
defeito que o #250 tirou do intertravamento, o de dizer um motivo preciso e
errado. Quem ainda não conhecer o 0x09 vê "recusado, motivo desconhecido", que é
degradação honesta; o `chan` do quadro carrega a **entrada** que a escrita
nomeou, porque é ela o assunto do quadro recusado.

Duas recusas de toque (`TEMPO_MORTO`, `PAR_ENERGIZADO`) vêm do intertravamento
do #250 e não são novidade de formato: o toque sempre passou pelo mesmo funil
`digital::set_state` que o barramento, e continua passando **para a saída
escolhida** — a guarda do guincho vale para o alvo configurado igual valia para
o posicional. O teto de bobinas é 8 desde o cartão #159; leia sempre o `detail`
em vez de cravar o número.

**Nas recusas de toque (origem local), o `chan` é a SAÍDA que não se moveu.**
Antes do #281 entrada e saída eram o mesmo número e nada distinguia as duas
leituras; agora divergem, e a escolha é deliberada: o que o operador vê não
acontecer é a luz, o `detail` do `PAR_ENERGIZADO` já é um índice de saída, e
misturar um índice de entrada no mesmo quadro seria incoerente. Nas recusas de
**escrita** o `chan` continua sendo a entrada, como acima. Quem consome precisa
saber qual é qual, e é o `refused_opcode` que diz: `0x00` = origem local = saída;
`0x4E` = escrita = entrada.

A recusa de toque é a que interessa à plataforma e é diferente de tudo que já
existe: ela chega com `refused_opcode = 0x00` (**origem local**) e **em
difusão**, porque não houve comando — alguém apertou um botão na parede e o
módulo disse não. No MT2 isso já está mapeado como
`MT2,<uin>,EVT,<seq>,NACK=<motivo>,CH=<n>,DET=<n>,OP=00,ORIG=local`
(ver `HANDOFF-recusa-comando-mt2.md`). **Nenhum `command_result` cobre esse
caso** — não há comando na nuvem a marcar como falho. Se ninguém consumir o
`EVT`, o operador aperta, a luz não acende, e não fica registro nenhum.

## O que a plataforma precisa saber antes de desenhar a tela

1. **O relé vai mudar sem comando.** Hoje `io-actions.ts` é deliberadamente
   não-otimista: o pill só muda quando o `do_mask` volta confirmando um comando
   que a plataforma mandou. Com a função ligada, o `do_mask` passa a mudar
   **sozinho**, porque alguém apertou um botão. Isso não é erro, não é comando
   perdido e não é desfecho de nada — é o estado do barco. O caminho que
   observa `do_mask` já trata mudança sem comando em voo como simples
   atualização; vale conferir que nenhum alerta ou telemetria a classifique como
   anomalia depois que a função existir na frota.

2. **O teto de 6 é do módulo, não da tela.** Um toque recusado consome o mesmo
   orçamento de corrente que um comando recusado. O `DET=` da recusa carrega o
   teto em vigor — é o que permite parar de cravar o 6 (item já aberto no
   `HANDOFF-recusa-comando-mt2.md`, `MAX_SAIDAS_SIMULTANEAS` em
   `apps/nautica/src/lib/api/iot.ts`).

3. **Nome.** Não chame de "pulso" na interface sem qualificar: o gateway já usa
   `pulso` para outra coisa — `IVS,SET,<node>,<ch>,1,<ms>` liga uma saída e a
   desliga sozinha depois de N ms, que é um pulso *de saída*. Esta função aqui é
   de *entrada*. Sugestão: **"interruptor de campainha"** ou **"botão de
   toque"**, que é como o instalador chama.

4. **É configuração de instalação, não de operação.** Quem liga isto é o
   instalador, uma vez, com o barco na frente. A tela natural é a de
   configuração do módulo (junto de nome de canal e ícone), não o painel de
   acionamento. E ela precisa mostrar o par entrada→saída explicitamente, porque
   é o que o eletricista precisa conferir contra a fiação.

5. **O par é um campo agora, não um rótulo.** Desde o #281 a tela tem de
   oferecer a escolha da saída, e não mais imprimir "IN3 → OUT3" como verdade
   fixa. O espelho da plataforma deixa de ser uma máscara de 8 bits e passa a
   ser uma lista de pares; o `enabled_mask` que este handoff descrevia até
   26/08/2026 **não existe mais no fio**. Duas entradas apontando para a mesma
   saída é instalação válida (interruptor paralelo) e a tela não deve tratar
   como conflito.

## O que falta — o elo do meio não existe

**O CM06 não tem comando MT2 para o I2008IF.** Conferido em
`matel-ivs-gateway-fw` nesta data: o gateway conhece a função de pulso só como
*origem* de recusa (`can_mtcp.h`, `serial_dot.c`), e não há caminho para
configurá-la. Ou seja, hoje a plataforma **não tem como ligar a função** nem
como ler como o módulo está configurado.

A cadeia completa precisa de três cartões, nesta ordem:

1. **Gateway CM06** — comando MT2 de escrita e de consulta do I2008IF, e
   publicação do relatório. É o bloqueio de todo o resto.
2. **Gateway Go / API** — transporte e persistência do estado relatado.
3. **Plataforma web** — a tela do instalador (este handoff).

Nada impede a plataforma de começar pelo desenho da tela e pelo modelo de
dados; o que ela não pode é prometer data de entrega antes do item 1.

## Como ver funcionando hoje, sem esperar a cadeia

Direto no barramento CAN, com o `can_tool.py` do repo do firmware:

```sh
# IN1 aciona a OUT4 -- o caso que o #281 abriu
python3 tools/can_tool.py set-function --node 0x41 --channel 0 \
                                       --function toggle --output 3

# o par posicional, que é o padrão (--output pode ser omitido)
python3 tools/can_tool.py set-function --node 0x41 --channel 0 \
                                       --function toggle --output positional

# como o módulo está configurado: sem --channel, pergunta os oito
python3 tools/can_tool.py get-function --node 0x41
```

Sem hardware nenhum, o emulador e a regressão headless:

```sh
python3.11 tools/pulso_sim.py     # 47 conferências, barramento virtual
python3.11 tools/can_node.py      # emulador; REPL aceita `press N` e
                                  # `pulse N V T` (aponta In N para Out T)
```

## Estado da validação em placa

**08/08/2026, formato antigo.** Rodado na CM2008_V5 (V5-rs, serial
`…9b73fd70`) pelo banco de testes (`cargo build --release --features bench`):
configuração pelo I2008IF de verdade, inversão do relé nos dois sentidos,
painel e parede concordando na mesma saída, e o toque recusado sob o teto de
bobinas saindo no barramento como recusa de origem local. Isso prova o caminho
comum — o pino, o relé, o debounce e a recusa de origem local — e **continua
valendo**, porque o #281 não mexeu em nenhum deles.

**26/08/2026, formato novo: NÃO rodou em placa.** Não havia sonda nem
CM2008_V5 na bancada no dia. O `bench_pulse` foi reescrito para exercer a
saída-alvo (IN1 → OUT4 de propósito, justamente para uma conferência não poder
passar lendo a saída de mesmo número da entrada), a escrita legada, a recusa
da saída inexistente, a consulta de um canal e a de todos — mas **não foi
executado**. O que fecha o cartão é o `tools/pulso_sim.py`, 47 conferências
num barramento virtual, com o emulador e o firmware carregando a mesma lógica;
não é vacuoso (ignorar o alvo no toque derruba 5, engolir a recusa derruba 3).
Quem puser uma placa e um J-Link na bancada: rode `./gravar.sh --bench` e
transcreva o passo 4 do `bench_protocol`.

O V4 **não recebeu o #281** — decisão do próprio cartão, o V4 é bancada — então
ele segue falando o formato antigo (escrita DLC 3, relatório DLC 2 com máscara).
Isso é divergência de propósito e não bug; quem for consumir de um V4 lê a
versão antiga deste handoff.

## Situação da cadeia (26/08/2026)

O elo do meio **continua não existindo**: o CM06 segue sem comando MT2 para o
I2008IF. A boa notícia do #281 é que isso deixou de ser dívida e virou
vantagem — como não há consumidor, a quebra do relatório não alcança a frota, e
**quem implementar o lado CM06 já implementa a versão nova**, sem passar pela
antiga. A ordem dos três cartões da seção *O que falta* não mudou.
