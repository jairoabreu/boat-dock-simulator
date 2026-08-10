# Handoff — função de pulso do iVS2008: interruptor de campainha aciona o relé

**Data:** 08/08/2026 · **Origem:** cartão #140 (firmware iVS2008, quadro 11) ·
**Para:** plataforma web (quadro 29) e gateway CM06 (`matel-ivs-gateway-fw`)

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

- O par é **fixo e posicional**: IN1↔OUT1 … IN8↔OUT8. Não há mapeamento
  arbitrário entrada→saída, e não é esquecimento: o caso geral é outro projeto
  (`docs/function_addressing_plan.md` no repo do firmware). As entradas de IN9
  para cima não têm relé para fazer par e **não aceitam a função**.
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

| operação  | direção     | DLC | carga                      |
|-----------|-------------|-----|----------------------------|
| escrita   | endereçada  | 3   | `[canal, função, 0x5A]`    |
| consulta  | endereçada  | 1   | —                          |
| relatório | **difusão** | 2   | `[seletor, máscara]`       |

- `canal` é 0-based e só 0–7 são válidos.
- `função`: `0` = nenhuma, `1` = inverter o relé do par.
- O `0x5A` é **trava**, não checksum. Não é sobre perder dado — a configuração é
  reversível — é sobre um quadro perdido ou mal endereçado fazer um relé passar
  a se mover sozinho quando uma boia de porão fecha.
- O relatório sai **a cada escrita aceita e a cada consulta**, nunca
  periodicamente. `máscara` é um bit por entrada, ligado = aquela entrada
  inverte o relé dela.

**Leia a máscara do relatório, não do que você mandou.** O módulo é o dono da
configuração: ela vive na memória não-volátil dele (NVS `PULSE` no V4, registro
FRAM no V5) e sobrevive a troca de firmware e a mudança de endereço CAN. Uma
cópia na nuvem é cache, e cache que ninguém revalida é como a plataforma acaba
mostrando uma função ligada num módulo que foi trocado.

## Recusas (I2008NK, cartão #141)

Três chegam desta função:

| motivo               | quando                                            | `detail`          |
|----------------------|---------------------------------------------------|-------------------|
| `FORA_DE_FAIXA` 0x02 | escrita num canal ≥ 8                             | nº de canais (8)  |
| `NAO_SUPORTADO` 0x03 | valor de `função` que o firmware não conhece      | 0                 |
| `LIMITE_SIMULTANEAS` 0x01 | **toque recusado**: seria a 7ª bobina        | teto em vigor (6) |

A terceira é a que interessa à plataforma e é diferente de tudo que já existe:
ela chega com `refused_opcode = 0x00` (**origem local**) e **em difusão**, porque
não houve comando — alguém apertou um botão na parede e o módulo disse não. No
MT2 isso já está mapeado como
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
   acionamento. E ela precisa mostrar o par IN(N)→OUT(N) explicitamente, porque
   é o que o eletricista precisa conferir contra a fiação.

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
python3 tools/can_tool.py set-function --node 0x41 --channel 0 --function toggle
python3 tools/can_tool.py get-function --node 0x41
```

Sem hardware nenhum, o emulador e a regressão headless:

```sh
python3.11 tools/pulso_sim.py     # 21 conferências, barramento virtual
python3.11 tools/can_node.py      # emulador; REPL aceita `press N`
```

## Estado da validação em placa (08/08/2026)

Rodado na CM2008_V5 (V5-rs, serial `…9b73fd70`) pelo banco de testes
(`cargo build --release --features bench`): configuração pelo I2008IF de
verdade, inversão do relé nos dois sentidos, painel e parede concordando na
mesma saída, e o toque recusado sob o teto de 6 bobinas saindo no barramento
como recusa de origem local. O V4 em campo tem o mesmo comportamento por
construção, mas a validação em placa dele depende de um adaptador CAN no host,
que a bancada não tem hoje.
