# Handoff — a recusa do módulo chega à nuvem: `ACK,seq,ERR=<motivo>,DET=<n>`

**Data:** 07/08/2026 · **Origem:** cartão #145 (gateway CM06,
`matel-ivs-gateway-fw`) · **Para:** gateway Go (`matel-gateway`) e plataforma
web (quadro 29)

Fecha a cadeia aberta pelo #106 (a web mediu a mentira) e pelo #141 (o módulo
passou a dizer NÃO no barramento). **O formato MT2 da recusa é definido pelo
#145** e a autoridade dele é `matel-ivs-gateway-fw/docs/MT2-recusa-de-comando.md`
— este handoff é o resumo para quem consome.

## O que mudou no que sobe

Antes, todo comando aplicado voltava `MT2,<uin>,ACK,<seq>,OK`, inclusive quando
o iVS2008 recusava por estourar o teto de 6 bobinas. Agora o gateway espera
250 ms por um `I2008NK` antes de confirmar, e a recusa sobe assim:

```
MT2,<uin>,ACK,<seq>,ERR=limite_simultaneas,DET=6
MT2,<uin>,ACK,<seq>,ERR=fora_de_faixa,DET=8
MT2,<uin>,ACK,<seq>,ERR=nao_suportado,DET=0
MT2,<uin>,ACK,<seq>,ERR=recusado,DET=<n>        motivo que o CM06 não conhece
```

**Nada a mudar no parser.** Foi por isso que o formato ficou assim:
`internal/protocols/mt2/parse.go` já recolhe os campos depois do `seq` num mapa
`chave=valor`, e `Message.IsAppliedAck()` já trata qualquer `ACK` com campo
`ERR` como insucesso. Um tipo novo (`MT2,...,NACK,...`) teria virado
`ErrUnknownKind` e a recusa se perderia de novo — o oposto do objetivo.

O que falta do lado Go/web:

1. **Levar o `DET=` adiante.** Hoje `handleAck` usa só `Fields["ERR"]` como
   motivo. `DET` é o número por trás do motivo — para `limite_simultaneas`, o
   **teto de bobinas em vigor**.
2. **Aposentar o `MAX_SAIDAS_SIMULTANEAS`** cravado em
   `apps/nautica/src/lib/api/iot.ts`. O 6 passa a vir de quem o aplica: se uma
   revisão de hardware mudar o orçamento de corrente, a mensagem ao operador
   acompanha sem deploy.

## Evento: recusa sem comando por trás

```
MT2,<uin>,EVT,<seq>,NACK=<motivo>,CH=<n>,DET=<n>,OP=<opcode_hex>,ORIG=<local|barramento>
```

`KindEVT` já é aceito pelo parser e hoje só vai para o stream de raw frames.
Vale um consumidor, porque `ORIG=local` (`OP=00`) é o caso que **nenhum**
`command_result` cobre: alguém apertou um botão de parede sob a função de pulso
(#140), o módulo recusou, e não há comando na nuvem a marcar como falho.
`ORIG=barramento` é recusa de comando vindo do BLE, ou recusa que chegou depois
da janela de 250 ms — nesse caso o comando já foi confirmado com `OK` e o
evento é a correção.

## ⚠️ O que NÃO mudou

**Ausência de recusa continua não sendo sucesso.** `OK` quer dizer "ninguém
recusou dentro da janela", não "o relé fechou": módulo antigo nunca emite
`I2008NK`, e o parque em campo é todo antigo. Quem encerra um acionamento
segue sendo o `do_mask` do `MT2,IO` seguinte — a regra que a web aplica desde o
#106 e que este cartão **não** substitui.

Caminho legado, para quem ainda o consome:
`ERR,IVS,SET,<node_hex>,<motivo>,<det>`.

## Como reproduzir sem hardware

`matel-ivs-gateway-fw/tools/cosim/` roda o emulador real do módulo contra o
firmware real do CM06 num barramento CAN virtual:

```bash
cd matel-ivs-gateway-fw/tools/cosim && make && python3.11 nack_cosim.py
```

Abre reproduzindo o traço de campo do
`HANDOFF-limite-6-saidas-ivs2008.md` — seis saídas ligadas, a sétima pedida três
vezes — e agora as três voltam com motivo em vez de `OK`.
