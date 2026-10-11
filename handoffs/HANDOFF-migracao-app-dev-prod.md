# HANDOFF — Migração do app publicado: dev → prod (sem tocar no cliente)

**Data:** 11/10/2026 · **Produtos:** app móvel (matel-mobile), plataforma web,
gateway de rastreadores (DOT460) · **Situação:** o app nas lojas (1.0.0+10)
aponta para `api-dev.marinetcs.com`, e há um cliente real e alguns demos
usando. São pouquíssimas peças em campo.

## Decisão

**Trocar o hostname, não desviar por UIN.** O nome que o app e os
rastreadores usam hoje (`api-dev.marinetcs.com` e o host do gateway TCP,
se for outro) passa a resolver para a **prod**. O ambiente de
desenvolvimento ganha um nome novo. Os equipamentos que precisam continuar
na dev são os internos (demo e bancada), que estão na nossa mão — os do
cliente não precisam de nada.

Por que não o desvio por UIN no gateway da dev:

- Resolve só o plano dos equipamentos. O app publicado continuaria lendo a
  dev e mostraria dados parados para os rastreadores desviados.
- Exige código de proxy nos dois sentidos (comando, ACK/NACK, consulta de
  configuração), com latência extra dentro da janela de 250 ms do comando.
- Risco de o mesmo frame ser gravado nos dois bancos.

O desvio por UIN fica como reserva para um caso só: rastreador configurado
por **IP** em vez de hostname (ver §4).

## 1. Dados — manual, não migra tudo

Cadastrar na prod à mão, antes do corte: empresas, usuários (senha nova ou
reset), embarcações, devices com UIN/IMEI, canais de IO, cercas, curvas de
consumo, labels dos módulos. Para telas 10.1" e CM350 que estejam em campo,
o token `mtd_` e a chave do CM350 também.

Regra: **todo UIN que vai chegar na prod precisa existir lá antes** do DNS
virar, senão a primeira conexão cai na tabela de órfãos e o app não mostra o
barco.

## 2. App (matel-mobile) — pronto

PR Marine-Telematics/matel-mobile#3: a base da API sai do código e vem de
`--dart-define=API_BASE_URL`. Sem o define o padrão continua a dev, então as
builds atuais não mudam. O WebSocket deriva da mesma base.

```bash
flutter build appbundle --dart-define=API_BASE_URL=https://api.marinetcs.com/api/v1
flutter build ipa       --dart-define=API_BASE_URL=https://api.marinetcs.com/api/v1
```

Com a troca de hostname o build atual já funciona na prod; a release nova
com a URL definitiva pode sair sem pressa. Efeitos colaterais esperados no
usuário: pede login uma vez (refresh token da dev não vale na prod) e, ao
logar, registra o token FCM na prod sozinho (acontece no boot). SAC não é
afetado (sistema separado em matel.ind.br).

## 3. DNS / ingress

1. Alguns dias antes: baixar o TTL dos registros envolvidos.
2. Certificado da prod cobrindo o nome antigo (SAN).
3. Apontar `api-dev.marinetcs.com` (HTTPS e porta 8350 do CM350) e o host
   do gateway TCP dos DOT460 para a prod.
4. Reconfigurar demo e bancada para o hostname novo da dev.

## 4. Rastreadores DOT460 (TCP)

- A conexão é longa: o rastreador só migra quando a conexão atual cair.
  Forçar fechando as conexões no gateway da dev, por UIN, fora de horário.
- Módulos 4G costumam resolver DNS uma vez e guardar o IP até reiniciar. Se
  algum insistir no IP antigo: reinício remoto ou esperar o próximo ciclo de
  energia do barco.
- O gateway da prod precisa aceitar o protocolo e o UIN antes do corte (§1).
- **Rastreador configurado por IP:** duas saídas sem ir ao barco. (a) Mover
  o IP junto, se for elastic IP ou equivalente. (b) Deixar no IP antigo um
  splice TCP mínimo que emenda toda conexão com a prod sem interpretar
  frames — a essa altura a dev já está em outro endereço, então não precisa
  filtrar por UIN.

## 5. Levantamento antes de marcar a data

Lista dos rastreadores do cliente e dos demos com o endereço gravado em
cada um (hostname ou IP). Só hostname → é DNS + §1 + §3.4. Algum IP → entra
o §4 último item.

## 6. Em aberto

- Nome novo do ambiente de desenvolvimento.
- Se o host do gateway TCP é o mesmo `api-dev` ou outro registro.
- Quem opera o reset de senha dos usuários do cliente na prod.
