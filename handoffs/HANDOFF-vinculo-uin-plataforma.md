# HANDOFF — Vínculo por UIN: o lado da PLATAFORMA (resposta)

**Data:** 07/08/2026 · **Responde a:** `HANDOFF-vinculo-uin.md`
**Cartão:** #128 (quadro 29) · **Pares:** #127 (CM06, quadro 9), #126 (tela, quadro 26)
**Commits:** backend `b55b2a2` + `14131ff` (`~/matel-web-platform-api`),
front `96df2d7` (`~/MaTel-web_platform`)

Este documento fixa o que a plataforma **emite** e **aceita**. É o contrato
contra o qual o firmware do CM06 e o da tela podem ser escritos hoje, sem
esperar deploy.

---

## 1. Forma do UIN no fio

Decimal, sem prefixo, sem zeros à esquerda. **Número** em JSON, **texto** no
MT2. `2608070000` (a iVS2408 da bancada).

Nunca aparece como UIN: o provisório `IVS-<rastreador>-<nó>` (cadastro antigo
sem serial) e o MAC hex do CM06/tela. Quem não anunciou identidade sai com
`uin: null` — identidade desconhecida se declara, não se inventa.

## 2. `GET /hmi/config` — o que mudou

`uin` entra **ao lado** do `node_id`, em cada canal e em cada módulo. O
`node_id` continua para a tela antiga.

```json
{
  "config_version": 24,
  "channels": [
    { "uin": 2608070000, "node_id": 65, "kind": "do", "channel": 6,
      "label": "Luz do salão", "area_id": "…" }
  ],
  "modules": [
    { "uin": 2608070000, "node_id": 65, "name": "Proa", "hw_id": "2608070000" }
  ]
}
```

Regras que a tela pode assumir:

- **`uin` presente → prefira-o.** Resolva `UIN → endereço` pela sua tabela
  viva do inventário. `node_id` no config é o último endereço OBSERVADO, e
  pode estar velho entre um inventário e o seguinte.
- **`node_id` pode ser `null`.** Significa: módulo cadastrado que ainda não
  apareceu no barramento. Ele não TEM endereço — não caia no 0x40.
- **`uin` pode ser `null`** no parque legado (módulo que nunca anunciou
  serial). Aí só resta o caminho antigo.
- `config_version` sobe sozinho: ele é o hash do corpo, e o campo novo já o
  muda na primeira leitura de cada barco. Nenhum passo manual.

`GET /hmi/state` ganhou `uin` por nó pela mesma regra — o snapshot da nuvem
também se casa por identidade.

## 3. `POST /hmi/inventory` — o reporte da tela

O endpoint **já existia** e continua no mesmo lugar; não há endpoint novo. O
que mudou é que ele passou a ser UIN-nativo:

```json
{
  "self_mac": "1020BAF3C8E6",
  "nodes": [
    { "node_id": 65, "uin": 2608070000 },
    { "node_id": 66, "uin": 2606200005 }
  ]
}
```

- `uin` (número) é o campo novo. `serial` (texto) continua aceito e é
  convertido — se o firmware já manda assim, **não precisa mudar nada**.
- Um nó sem identidade nenhuma não é erro (firmware antigo): ele volta
  contado em `unidentified` e o cadastro dele segue por endereço.

Resposta:

```json
{ "received": 2, "matched": 1, "created": 1, "renumbered": 1,
  "learned": 0, "unidentified": 0, "config_changed": true, ... }
```

**`config_changed: true` = puxe `/hmi/config` agora**, sem esperar o próximo
poll. É o que fecha o ciclo "inventário → config" do handoff: o módulo que
acabou de ser criado ou reendereçado já entra na config da mesma passada.

O que o inventário faz do lado de cá, e vale a pena a tela saber:

- casa por UIN (não por endereço);
- **batiza** um módulo cadastrado à mão que ainda não tinha identidade;
- **cria** o módulo desconhecido, pendente de nome/área pelo operador;
- no reendereçamento, **arrasta a configuração junto** (canais e snapshot).
  Antes o device renumerava e o `node_id` dos canais congelava no endereço
  velho: a config que a tela antiga recebia passava a apontar para o vizinho
  — o #125 reconstruído do lado da nuvem. Uma troca A↔B de endereços entre
  dois módulos é aplicada em dois passes e não colide.

## 4. Comando remoto — o que chega ao CM06

Sem mudança de gramática: é o mesmo MT2 da etapa 5 da `ARQUITETURA-uin-v2.md`.

```
MT2,<uin>,CMD,<seq>,OP=SET,CH=<n>,ST=<0|1>
```

Via 4G dentro do envelope intocado do rastreador
(`DOT232;<counter>;<imei>;<payload>`), via WiFi cru. `<seq>` é o mesmo counter
do frame legado, em hex de 4 dígitos — a correlação do ACK é pelo par
**(UIN, seq)**.

O que mudou aqui é a PROCEDÊNCIA do `<uin>`: ele agora sai da coluna
`devices.uin` (u64, migração 084) em vez de um campo de texto que também
guardava IMEI e MAC. Efeito prático para o CM06: **nenhum** — o mesmo texto
decimal continua chegando.

Novidade útil: um módulo com UIN e **sem** endereço de barramento é enviado
**só por MT2**, sem frame legado junto (não há nó para montá-lo). É o caso do
módulo recém-cadastrado que a tela ainda não inventariou.

Pulso (`io_pulse_output`) segue exigindo endereço — ele só existe no frame
legado. Sem endereço, a plataforma recusa com 409 explícito em vez de
prometer um pulso que ligaria e nunca desligaria.

## 5. Honestidade — o que a plataforma recusa

Mesma regra das outras duas pontas, aplicada aqui primeiro:

| Situação | Resposta |
|---|---|
| `uin` que não existe naquele barramento | `404 módulo <uin> não está cadastrado nesta embarcação` |
| URL aponta um módulo e o corpo manda outro `uin` | `409` com os dois UINs no texto |
| `uin` já cadastrado em outro equipamento | `409` — um módulo não fica em dois barcos |
| cadastro tenta ocupar endereço de outro módulo | `409` — reendereçamento vem do inventário |

Nenhuma dessas escolhe um destino em silêncio. Logs saem sempre no formato
combinado: `uin 2608070000 @ 0x46`, com `?` na metade que faltar.

## 6. Ainda em aberto

- A migração **084 não rodou** em dev nem em produção (esta máquina não tem
  Postgres). Até rodar, `devices.uin` não existe e o código cai no `hw_id`
  como rede de segurança — comportamento igual ao de hoje.
- Nada foi validado na bancada ponta a ponta: falta o par CM06 (#127) + tela
  (#126) para o teste com os dois módulos no barramento.
