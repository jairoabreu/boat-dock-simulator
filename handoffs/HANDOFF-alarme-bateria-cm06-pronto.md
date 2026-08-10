# Handoff — alarme de bateria: o elo do CM06 está pronto (e falta o do módulo)

**Data:** 08/08/2026 · **Origem:** cartão #175 (gateway CM06, quadro 9) ·
**Para:** plataforma web / API (cartão #173, quadro 29), `matel-gateway` (Go) e
firmware do iVS-2408 (cartão #174, quadro 11)

**Resposta a** `HANDOFF-alarme-bateria-ivs2408.md`.

> **Resumo em uma linha:** o CM06 já fala o `AL`/`AL?` e já publica o relatório e
> o alarme na forma que a plataforma pediu — **sem uma vírgula de diferença**. O
> que falta para a cadeia funcionar de ponta a ponta é o item 1: o módulo ainda
> não tem o `I2008AL`.

## O que ficou pronto (item 2 da tabela do seu handoff)

**A autoridade do formato é `docs/MT2-alarme-bateria.md`** no repo
`matel-ivs-gateway-fw`. Ele detalha o que está abaixo, mais o quadro CAN e os
porquês.

Descida, exatamente como no §5 do seu handoff:

```
escrita:   MT2,<uin>,CMD,<seq>,AL,CH=<0..7>,MIN=<mV|->,MAX=<mV|->
consulta:  MT2,<uin>,CMD,<seq>,AL?,CH=<0..7|FF>
```

Subida, idem:

```
relatório: MT2,<uin>,EVT,<seq>,AL=<ch>,MIN=<mV|->,MAX=<mV|->,NODE=<xx>
alarme:    MT2,<uin>,EVT,<seq>,ALM=<ch>,SIDE=<lo|hi>,MV=<mV>,NODE=<xx>
```

Confirmado ponto a ponto:

- **`-` é limite desligado**, na descida e na subida. Nunca vira `0` no caminho,
  e um `0` que você mandar é gravado como limite de verdade. A distinção não se
  perde no fio: no quadro CAN ela é uma **flag**, não um valor sentinela.
- **Destino por UIN**, resolvido na injeção.
- **O `0x5A` é montado no CM06** e não aparece no MT2.
- **`CH ≥ 8` volta `ACK,<seq>,ERR=fora_de_faixa,DET=8`** e nada vai ao
  barramento.
- **Milivolts inteiros de borne**, e o CM06 **não converte nada** — a conta de
  escala continua sendo de vocês (`io_escala.py` / `io-analogica.ts`).
- **Nada é guardado aqui.** O relatório vale no instante em que sai e é publicado
  na hora, como o `I2008IF`. Configuração mexida por fora (`can_tool.py` na
  bancada) aparece na consulta seguinte. É isso que sustenta o `lido_em` do §6:
  ele é o carimbo do **relatório**.

## Uma recusa a mais do que vocês pediram

Além do `CH ≥ 8`, o CM06 recusa localmente **`MIN`/`MAX` que não seja `-` nem um
inteiro de 0 a 65535**, com `ERR=nao_suportado,DET=0`.

O motivo é o erro caro do seu §2, na versão que passa despercebida: `MIN=11.8`
(volts em vez de milivolts) viraria **11 mV** num parser distraído — um limiar de
verdade, gravado, que nunca dispara, e que ninguém descobre até a bateria morrer.
Recusar alto é o lado certo de errar.

## O que o CM06 deliberadamente NÃO julga

`MIN ≥ MAX` e "limite acima do que a entrada mede" **vão ao barramento** e
voltam como `I2008NK` do módulo, com o `DET` **dele**. Não é omissão: os dois
são política de quem mede, e a faixa útil (~25 V hoje, §3) muda com revisão de
hardware. Cravar aqui um teto de tensão repetiria exatamente o "6 fixo" do #159 —
a nuvem afirmando um número que pertence a quem o aplica.

Quando o item 1 existir e recusar, vocês recebem
`ACK,<seq>,ERR=<motivo>,DET=<n>` pelo caminho normal, já em produção desde o
#145.

## O que o elo Go precisa ganhar (nada estrutural)

Duas projeções sobre o `EVT` que já existe — `AL()` e `ALM()`. **Nenhum tipo
novo** no parser: as duas linhas são `EVT` com campos `K=V` e atravessam o
`parse.go` de hoje, pela mesma razão medida no #158 (um tipo `AL` viraria
`ErrUnknownKind` **e** `RecordUnknownDevice`, ou seja, ruído de "equipamento
desconhecido" a cada escrita). `RecusaDoEvento()` já devolve `false` sem `NACK=`,
então nada existente muda de comportamento.

O `EVT` passa a ter quatro formas, distinguidas por campo: `NACK=` recusa, `IF=`
campainha, `AL=` configuração de alarme, `ALM=` alarme.

## O que AINDA BLOQUEIA a ponta (item 1 — cartão #174, quadro 11)

O iVS-2408 não tem o `I2008AL`. Enquanto isso:

- um `AL,...` enviado hoje **sai no barramento** e ninguém do outro lado o
  atende. O ACK volta `OK`, que significa **"ninguém recusou"** — e não "está
  gravado", pela regra de sempre;
- **nenhum relatório e nenhum alarme sobem**, porque não há quem os emita. A tela
  da web não deve mostrar limites "gravados" antes do primeiro `EVT` com `AL=`;
- o `battery_detector.py` continua sendo a única vigia, e continua valendo depois
  — para quem não está a bordo.

Recomendação para a web: só habilitar o botão de gravar depois que a API tiver
visto ao menos um relatório daquele UIN (o `204` do §6 é exatamente esse estado).

## Números que o módulo precisa registrar (§5 e §9)

O CM06 **não filtra** alarme: publica o que o módulo emitir, na ordem em que
chegar. Então os dois números abaixo são do #174, e o pedido é só que fiquem
**escritos**:

- a **histerese / banda morta** (sugestão do handoff: 0,3 V de retorno, mais um
  tempo mínimo antes de emitir);
- a régua do **canal sem fio** (0,5 V no borne). Se ela mudar, muda nos dois
  lados — está em `docs/MT2-alarme-bateria.md` do nosso lado.

E o opcode: **0x4B**, livre hoje (conferido em
`~/CM2008/Firmware/V5-rs/src/types.rs`), provisório pela mesma ressalva do
0x4C/0x4D/0x4E. O quadro está no bloco `MTCP_CMD_I2008AL` de `main/can_mtcp.h`,
que é espelhado com `~/CM2008` e com a tela P4.

## Como isto foi verificado sem silício

`tools/cosim/alarme_bateria_cosim.py` — 34 conferências com o firmware real do
CM06 rodando no hospedeiro, num barramento CAN virtual.

⚠️ **Com uma ressalva declarada:** como o emulador do módulo ainda não implementa
o 0x4B, o lado do **módulo** é um substituto do próprio teste, escrito contra o
§4 deste handoff. Ele prova que o CM06 conversa com um par que segue o contrato;
**não** prova que o módulo vai segui-lo. O script procura o suporte nativo a cada
execução — quando o #174 gravar `CMD_ANALOG_ALARM` no `can_node.py`, o substituto
sai de cena sozinho e o mesmo teste vira cossimulação inteira.
