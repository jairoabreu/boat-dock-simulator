# Handoff — alarme de bateria gravado no módulo: o que a plataforma precisa

**Data:** 08/08/2026 · **Origem:** cartão #173 (plataforma web, quadro 29) ·
**Para:** firmware do iVS-2408 (`~/CM2008`, quadro 11), gateway CM06
(`matel-ivs-gateway-fw`, quadro 9) e tela 10.1" (`matel-ivs-display-p4`,
quadro 26)

> **Resumo em uma linha:** existe um tipo novo de entrada analógica —
> **bateria** — com mínimo e máximo de alarme, e o pedido do cartão é que
> esses limites fiquem **gravados no módulo**, que passa a comparar sozinho e
> a avisar mesmo com o barco sem sinal.

A metade da web está pronta e no ar em dev: o canal existe, o instalador
configura, a tela de bordo recebe pelo `/hmi/config` e o alerta nasce na
plataforma. O que **não** existe é o elo do meio — o módulo não tem onde
guardar limite de analógica, e o CM06 não tem comando para escrevê-lo. É a
mesma cadeia do interruptor de campainha (#154 → #158), e este documento é o
contrato que a web quer consumir, para que os cartões de firmware não
precisem adivinhar a forma.

Estado da cadeia:

| # | onde | o que falta | quem |
|---|------|-------------|------|
| 1 | iVS-2408 | guardar os limites em FRAM, comparar e emitir o alarme | quadro 11 **(bloqueio de tudo)** |
| 2 | CM06 | comando MT2 de escrita/consulta + publicar relatório e alarme | quadro 9 |
| 3 | Go + API | transporte, persistência por UIN e evento ao vivo | `matel-gateway` / `matel-api` |
| 4 | tela 10.1" | desenhar `ai_role='battery'` e destacar o alarme | quadro 26 |
| 5 | web | ligar o botão de gravar ao envio | quadro 29 — **feito no #180** (ver o aviso no §6) |

---

## 1. O que a plataforma já modelou (e que o resto tem de encaixar)

`ai_role='battery'` num canal `ai`, com o mesmo `ai_alarm` que já serve a
tanque e temperatura:

```json
{
  "node_id": 65, "kind": "ai", "channel": 2,
  "label": "Banco de serviço",
  "unit": "V", "volt_min": 0, "volt_max": 25,
  "scale_min": 0, "scale_max": 25,

  "ai_role": "battery",
  "ai_alarm": { "low": 11.8, "high": 15.0,
                "cooldown_min": 30, "notify_company_users": true }
}
```

Regras impostas na porta da API (422 explícito, não coerção):

- `unit='V'` obrigatório;
- escala obrigatória e com `scale_min < scale_max`;
- limites **dentro** da escala — limite fora dela é alarme que nunca dispara;
- `low < high` quando os dois existem; cada um é opcional (banco de serviço
  costuma alarmar só por baixo).

## 2. A regra que evita o erro caro: **o limite desce em VOLTS DE BORNE**

> O número que o operador digita está na **unidade escalada do canal**. O
> módulo compara com a tensão que ele mede **no borne**. Quem grava traduz.

Com leitura direta os dois são o mesmo número. Com um divisor externo 1:2
(0–12 V no borne = 0–24 V no banco), um limite de **23,4 V no banco** são
**11,7 V no borne** — gravar 23,4 pediria uma tensão que aquele borne nunca
vê, e o alarme jamais dispararia.

A conta é a inversa exata da escala, e está implementada e sob teste dos dois
lados da plataforma:

- `matel/services/io_escala.py::limite_no_borne` (API)
- `apps/nautica/src/lib/api/io-analogica.ts::limiteNoBorne` (web)
- testes: `tests/test_bateria.py`, `apps/nautica/tests/io-bateria.test.ts`

**O módulo não precisa saber nada disso.** Ele recebe volts e compara volts —
é o mesmo desenho do tanque, em que a tela não conhece a curva do sensor.

## 3. Faixa útil: 25 V, e o que isso decide

Medido em placa e documentado em `~/CM2008/firmware/V5-rs/src/analog.rs`: a
entrada é de 0–12 V nominais no borne e a faixa útil é **~25 V**, não os 36 V
que o divisor 10 k/110 k sugere — o modo comum do buffer LMV321 acaba em
VCC−1,0 V.

Consequências, e elas são de produto:

- **Banco de 12 V lê direto.** 10–15 V cabem com folga.
- **Banco de 24 V não cabe**: em carga (28,8 V) a leitura satura. Exige
  divisor externo, declarado na escala do canal. A tela do instalador avisa
  ao configurar um limite acima de 25 V — mas o aviso é da web, e a decisão
  de fiação é do campo.
- Se um lote futuro trouxer entrada de faixa maior, é a escala do canal que
  muda, não o contrato.

## 4. O que o iVS-2408 precisa ganhar (quadro 11)

Mesmo desenho do `I2008IF` (0x4E), que já resolveu o problema equivalente:
configuração que **mora no módulo**, sobrevive a troca de firmware e a
mudança de endereço CAN, e nasce desligada.

```
escrita    endereçada  [canal, flags, min_mV u16 LE, max_mV u16 LE, 0x5A]
consulta   endereçada  [canal]           (0xFF = todos)
relatório  DIFUSÃO     [canal, flags, min_mV u16 LE, max_mV u16 LE]
alarme     DIFUSÃO     [canal, lado, valor_mV u16 LE]
```

Proposta de opcode: **0x4B (`I2008AL`)** — livre hoje no bloco 0x41–0x4F, com
a mesma ressalva provisória do 0x4C/0x4D/0x4E (registro canônico do MTCP
inacessível; mudou lá, muda aqui, no `~/CM2008` e no `can_mtcp.h` da tela).

Pontos que a plataforma pede explicitamente:

1. **Persistir em FRAM**, ao lado do `PULSE_ADDR` — um registro por canal,
   com `flags` dizendo quais limites estão ligados. Limite desligado não é
   "limite zero": zero é um alarme permanente.
2. **Milivolts inteiros, não float.** 16 bits cobrem 0–65,535 V com resolução
   de 1 mV, muito além dos ~25 V úteis, e não pagam o custo de f32 no fio nem
   ambiguidade de representação. O `I2008AS` difunde f32 porque é leitura; o
   limite é configuração e vale a forma mais dura.
3. **A trava 0x5A**, pela mesma razão do `I2008IF`: um quadro perdido ou mal
   endereçado não pode mudar o limiar de alarme de um banco de baterias.
4. **O relatório é a única fonte do estado.** A nuvem guarda o que MANDOU
   gravar; quem diz o que está gravado é a placa. Configuração mexida por
   fora (`can_tool.py` na bancada) tem de aparecer na consulta seguinte.
5. **Histerese no alarme.** Uma bateria oscila em volta do limiar quando um
   motor de partida puxa corrente. Sem banda morta o módulo emite uma
   enxurrada de eventos. Sugestão: 0,3 V de retorno e um mínimo de tempo
   acima/abaixo antes de emitir; o número exato é do firmware, que conhece a
   cadência do ADC — só registre qual foi.
6. **Faixa recusada como recusa, não em silêncio:** canal ≥ 8, min ≥ max ou
   limite acima do que a entrada mede devem voltar `I2008NK` com motivo, do
   mesmo jeito que o teto de bobinas (#145). `ACK,OK` com nada gravado é o
   defeito que já custou três diagnósticos errados.

## 5. O que o CM06 precisa falar (quadro 9)

Mesma família dos comandos que já existem — e, do aprendizado do #158, já na
forma que **atravessa o parser de hoje** (`EVT` com campos `K=V`, nunca tipo
novo, nunca campo posicional no lugar do `seq`):

```
escrita:    MT2,<uin>,CMD,<seq>,AL,CH=<0..7>,MIN=<mV|->,MAX=<mV|->
consulta:   MT2,<uin>,CMD,<seq>,AL?,CH=<0..7|FF>
relatório:  MT2,<uin>,EVT,<seq>,AL=<ch>,MIN=<mV|->,MAX=<mV|->,NODE=<xx>
alarme:     MT2,<uin>,EVT,<seq>,ALM=<ch>,SIDE=<lo|hi>,MV=<mV>,NODE=<xx>
```

- `-` em `MIN`/`MAX` é limite DESLIGADO. Um `0` seria um limite de verdade.
- Destino por UIN, resolvido na injeção, como todo o resto desde o #125.
- O `0x5A` é montado no CM06 e não sobe no MT2.
- Canal ≥ 8 volta `ACK,<seq>,ERR=fora_de_faixa,DET=8` sem ir ao barramento,
  como o `IF`.

## 6. O que a API vai expor (quadro 29, depois de 1–2)

```
GET /devices/{device_id}/io/bateria?uin=<uin>
→ 200 { "uin": …, "node_id": 70, "canais": [
         { "channel": 2, "min_mv": 11800, "max_mv": 15000 } ],
        "lido_em": "2026-08-08T12:00:00Z" }
→ 204 quando o módulo nunca relatou

PUT /devices/{device_id}/io/bateria
    { "uin": …, "channel": 2, "min_mv": 11800, "max_mv": 15000 }
→ 202 { "command_id": "…" }
```

`lido_em` é o carimbo do RELATÓRIO, não o da linha no banco — é ele que diz à
web se a resposta ainda vale. Persistência **por UIN**, nunca por endereço:
módulo trocado tem UIN novo, e é isso que impede a placa nova de herdar o
limite da velha.

> ### ⚠️ O que a API expôs de verdade (cartão #180, 08/08/2026)
>
> A forma acima era a proposta. O que **entrou** segue o precedente do
> interruptor de campainha (#161), e a diferença é deliberada:
>
> ```
> PUT  /devices/{device_id}/io/bateria/{channel}   iot:configure → 202
>      { "uin": …, "min_mv": 11800, "max_mv": 15000 }   (null = desligado)
> POST /devices/{device_id}/io/bateria/consulta    iot:read      → 202
>      { "uin": …, "channel": 2 }   (channel ausente = os oito, CH=FF)
> ```
>
> **Não existe o `GET`, e não há persistência.** O relatório sobe como `EVT`
> com `AL=` e a web o lê do stream de frames crus, pelo mesmo caminho por onde
> já lê a máscara da campainha — que é exatamente o motivo de o CM06 ter
> escolhido essa forma (§5 do handoff dele). Guardar uma cópia na nuvem
> repetiria o cache de UIN do #156: um valor que o barramento não confirmou,
> pronto para ser atribuído à placa errada depois de uma troca no mesmo
> endereço. O `lido_em` continua existindo e continua sendo o carimbo do
> relatório — só que ele vive no cliente, com validade de 60 s, e não no banco.
>
> A consulta é `POST` porque põe uma linha no barramento; o `204 quando o
> módulo nunca relatou` virou o estado **"não lido"** da tela, que é a mesma
> informação sem uma tabela para mantê-la.

## 7. O que a tela 10.1" precisa desenhar (quadro 26)

O `/hmi/config` **já manda** `ai_role: "battery"` com `ai_alarm` — é aditivo,
e firmware que ignore o campo continua funcionando. O que se pede:

- desenhar como leitura de tensão (`unit` do canal, 2 casas — 12,60 V, não
  12,6 V: a segunda casa é o que distingue banco em repouso de banco em
  carga);
- **destacar ao cruzar qualquer um dos limites**, com a mesma régua sugerida
  para temperatura (normal / atenção a 10% do limite / alarme);
- alarmar **localmente**, sem depender da nuvem. É melhor assim, e é o mesmo
  argumento do §6 do handoff de tipos especiais;
- papel desconhecido cai em genérica, nunca falha.

Quando o item 1 existir, o alarme passa a ter **duas** origens (o módulo e a
própria tela). Não é duplicidade a resolver agora: quem chegar primeiro
acende, e o `cooldown_min` já governa a repetição.

## 8. O que já está no ar do lado da web (cartão #173)

- `apps/nautica/src/lib/api/io-analogica.ts` — a escala e a volta dela.
- `apps/nautica/src/components/iot/IoChannelsConfig.tsx` — o tipo novo, os
  limites e o bloco "o que vai gravado no módulo" (mostra os volts de borne).
- `matel/services/io_escala.py` — a mesma conta do lado da API.
- `matel/realtime/battery_detector.py` — enquanto o módulo não vigia, é ele
  que cria o alerta da plataforma (`battery.low` / `battery.high`), lendo o
  snapshot que já chega. Continua valendo depois, para quem não está a bordo.
- Migração `085_ai_role_battery`.

E o que o **#180** acrescentou, fechando o item 5:

- `apps/nautica/src/lib/api/io-bateria.ts` — a tradução para milivolt de borne,
  a leitura do relatório (`AL=`) e a comparação que decide entre "gravado no
  módulo" e "plataforma e módulo divergem". `io-bateria-actions.ts` é o ciclo
  (consulta ao abrir, gravação sob demanda, relatório decidindo).
- `IoChannelsConfig.tsx` — o botão **Gravar no módulo**, o selo não-otimista e
  o aviso de dessincronia.
- API: os dois endpoints do aviso no §6 e os frames `AL`/`AL?`.
- `matel-gateway`: as projeções `LimitesDeAlarme()`/`AlarmeDeAnalogica()` e —
  o que importa de verdade — o `CH=` de um `AL` **não** correlaciona recusa de
  saída, pela mesma razão que o `IF` já não correlacionava.

Fica **em aberto** e é do quadro 29: o `ALM=` ainda não vira alerta da
plataforma. Quem cria alerta de bateria hoje continua sendo o
`battery_detector.py`, lendo o snapshot — o alarme que o módulo emite sozinho
está no fio e no log, sem consumidor na nuvem.

## 9. Uma decisão que ficou registrada

Leitura abaixo de **0,5 V no borne** é tratada como **canal sem fio**, não
como bateria morta: um banco descarregado ainda marca 10–11 V. Sem essa
régua, todo canal cadastrado antes de o eletricista puxar o cabo mandaria
WhatsApp de "bateria baixa" a cada 30 minutos. Se o firmware alarmar por
conta própria, vale a mesma régua lá — e o número, se mudar, deve mudar nos
dois.
