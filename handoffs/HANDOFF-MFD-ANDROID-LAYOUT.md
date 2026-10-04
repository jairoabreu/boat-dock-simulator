# Handoff — layout e menus da MFD Android 10"

Data: 04/10/2026. Aplicativo Flutter `br.ind.matel.ivshmi`, versão **0.9.0+17**.
Repositório: `Marine-Telematics/matel-ivs-android`, branch `codex/ihm-android`.
Código local: `/Users/jairo/MaTel/matel-ivs-android`.

## Decisão confirmada pelo usuário

A MFD permite escolher o que aparece na interface em **Ajustes → Layout e menus**. As escolhas feitas localmente têm prioridade permanente. O usuário esclareceu que o botão **“Sobrescrever estrutura de menus da plataforma web”** significa **usar o layout da web na tela**.

A sincronização normal consulta a web e envia o estado local, mas **nunca aplica automaticamente o layout da web**, nem no primeiro vínculo, na inicialização, após reconexão ou porque uma revisão web é mais recente. A única importação ocorre ao clicar nesse botão; ela faz uma nova consulta e salva o resultado localmente antes de mudar a interface. Depois disso, o layout importado passa a ser a escolha local e segue a mesma prioridade. Uma edição local iniciada durante a importação cancela a importação.

**Implementado no Android. A plataforma web deve implementar o contrato abaixo.** Os endpoints são novos, independentes do cadastro da embarcação e de `/hmi/config`. Na bancada, a versão 0.9.0 já está instalada; o servidor retornou recurso indisponível, e a MFD preservou as escolhas e exibiu a pendência. A funcionalidade local e a persistência foram verificadas na placa; confirmação/importação bem-sucedida foram cobertas nos testes automatizados. Não confundir esta especificação com confirmação de backend já publicado. A validação real está registrada em `docs/validacao-layout-0.9.0.md`.

## Interface e alcance

- Menus do carrossel: Iluminação, Baterias, Tanques, Bombas, Climatização, Âncora, Mapa e Previsão do tempo.
- Atalhos superiores: Entradas e saídas, Alarmes e Ajustes. Os atalhos das páginas internas obedecem às mesmas escolhas.
- Indicadores da inicial: Bateria de serviço, Água doce, Iluminação e Amarra, configurados separadamente dos menus.
- **Ajustes fica sempre visível**. Todos os outros menus e indicadores podem ser ocultados, inclusive todos de uma vez. O espaço do carrossel/indicadores é recuperado pela imagem.
- Ocultar menus não desliga serviços, GPS, equipamentos ou alertas de cercas/velocidade. Não altera configurações CAN, GPIO, boot ou Android. CAN continua sem integração física nesta versão.
- Logo, identificação do barco, alternância dia/noite e aviso de dados simulados/sem módulos permanecem visíveis. Esta versão configura visibilidade; não altera ordem, tamanho ou posição dos itens.

## Separação obrigatória no backend

Guardar dois documentos por **equipamento MFD autenticado**, não apenas por embarcação:

1. `desired` / layout da web: edição preparada no portal, com revisão opaca `web_revision`. É a origem do botão de importação.
2. `reported` / layout efetivamente usado na MFD: último snapshot local confirmado pelo servidor, com `installation_id` e `local_revision`.

**PUT de reported não modifica desired.** Se a sincronização sobrescrever o documento desired com o local, o botão deixará de conseguir importar a edição feita no portal. O portal deve mostrar “Em uso na MFD” e “Preparado na web” separadamente, indicando quando divergem; não apresentar uma edição web como aplicada na tela antes de receber o reported correspondente.

O vínculo usa o **Bearer token de equipamento já salvo na MFD**, igual ao acesso HMI existente. Resolver equipamento, empresa e embarcação no servidor. Não enviar `X-Company-Id`, MAC, serial do SoC ou token no JSON. `installation_id` é apenas a sequência de revisões dessa instalação do aplicativo, **não é credencial nem ID de vínculo**. Duas MFDs na mesma embarcação podem ter layouts diferentes.

## Contrato HTTP implementado

Base normalizada pela MFD: `<base>/api/v1/`. Cabeçalhos: `Authorization: Bearer <token-do-equipamento>` e `Accept: application/json`. PUT também envia `Content-Type: application/json`.

### GET `/api/v1/hmi/menu-layout`

Retorna **200**, com snapshot completo do layout preparado na web:

```json
{
  "schema_version": 1,
  "web_revision": "web-2026-10-04-001",
  "layout": {
    "menus": {
      "lighting": true,
      "batteries": true,
      "climate": false,
      "tanks": true,
      "pumps": true,
      "anchor": true,
      "routes": true,
      "weather": true,
      "alarms": true,
      "io": true,
      "settings": true
    },
    "indicators": {
      "service_battery": true,
      "fresh_water": true,
      "lighting": true,
      "anchor": false
    }
  }
}
```

Sem layout web configurado, responder **200** explicitamente:

```json
{"schema_version":1,"web_revision":null,"layout":null}
```

Não usar 404 para “ainda não configurado”: a MFD interpreta 404/405/501 como recurso ainda indisponível no servidor. Na sincronização normal, ela faz este GET antes do PUT; portanto ambos os endpoints devem ser disponibilizados juntos. GET nunca tem efeito de escrita na MFD.

### PUT `/api/v1/hmi/menu-layout/reported`

Snapshot completo das escolhas locais. Exemplo ilustrativo de uma importação:

```json
{
  "schema_version": 1,
  "installation_id": "00112233445566778899aabbccddeeff00",
  "local_revision": 12,
  "adopted_web_revision": "web-2026-10-04-001",
  "layout": {
    "menus": {
      "lighting": true,
      "batteries": true,
      "climate": false,
      "tanks": true,
      "pumps": true,
      "anchor": true,
      "routes": true,
      "weather": true,
      "alarms": true,
      "io": true,
      "settings": true
    },
    "indicators": {
      "service_battery": true,
      "fresh_water": true,
      "lighting": true,
      "anchor": false
    }
  }
}
```

Responder **200 com o mesmo snapshot persistido**. A MFD valida `schema_version`, `installation_id`, `local_revision` e o conteúdo completo de `layout` antes de marcar “confirmado pela plataforma”. Não responder 204 nem apenas `{ "ok": true }`. Campos extras são permitidos. Um PUT bem-sucedido deve confirmar o envio mesmo que `desired` tenha mudado desde o último GET; não há dependência entre as revisões web e local.

- `installation_id`: 32 dígitos hexadecimais minúsculos, aleatórios; mantido entre atualizações e reinícios do app. Reinstalação com remoção de dados gera outro ID.
- `local_revision`: inteiro não negativo; inicialmente 0, incrementado a cada edição/importação salva. Não é timestamp. Não comparar valores entre instalações.
- `adopted_web_revision`: string da revisão importada ou `null`. Uma edição local posterior limpa esse campo. Não é pedido de importação, nem autorização do servidor para forçar mudanças.
- `web_revision`: string opaca não vazia, até 128 caracteres, regex `^[A-Za-z0-9._:-]{1,128}$`. Alterar quando o documento web mudar. A MFD não ordena essas strings.
- `schema_version`: 1. `menus` e `indicators` devem conter todos os IDs conhecidos abaixo, com booleanos reais, nunca strings, números ou null.
- `menus.settings` deve ser `true`; caso contrário a MFD rejeita o documento inteiro.
- Cada mapa aceita até 64 entradas, IDs com regex `^[a-z][a-z0-9_]{0,63}$`. IDs futuros válidos são preservados no JSON, mas não criam funções na interface. Uma evolução que acrescente IDs obrigatórios precisa prever migração/compatibilidade das versões antigas.

### Idempotência e concorrência no servidor

Persistir atomicamente reported e a confirmação. Para o mesmo equipamento + instalação, aceitar revisão maior; repetir revisão idêntica com mesmo conteúdo deve ser idempotente. Rejeitar revisão menor ou mesma revisão com conteúdo diferente (409). Não usar relógio do Android para arbitrar prioridade.

Para reinstalação, tratar o novo `installation_id` como nova sequência e guardar a instalação substituída como aposentada. Requisições atrasadas da instalação aposentada devem retornar 409, sem apagar reported da instalação atual. Não implementar “última chamada sempre vence” entre instalações. Toda operação continua exigindo o token do equipamento; um ID de instalação isolado não autoriza nada.

Mudança de token/base na MFD mantém as escolhas locais, cancela a sessão HTTP antiga e invalida a confirmação para o novo destino. O estado passa a ser reportado ao vínculo atual. Desvincular não apaga o layout local. O cliente ignora confirmações atrasadas de outra sessão/revisão.

### Falhas e limites

- 401/403: acesso recusado, manter escolhas locais.
- 404/405/501: endpoint indisponível, mostrar pendência local.
- Demais status, inclusive 409: não confirmar; tentar novamente em próxima sincronização.
- Redirecionamentos nunca são seguidos, evitando encaminhar credenciais. Publicar os caminhos finais sem redirect.
- Respostas limitadas a **32 KiB**, timeout total de 20 segundos, conexão de até 15 segundos. JSON inválido/incompatível não é aplicado.
- Sem internet, importação não utiliza uma cópia web antiga; mantém o layout atual e informa falha.

## Persistência e frequência no Android

`menu-layout.json` no `noBackupFilesDir` do aplicativo, separado do cache do barco. Escrita em temporário, flush e rename atômico. Não contém token; a confirmação usa fingerprint SHA-256 do destino autenticado e a revisão confirmada. Não enviar esses campos privados ao backend.

Sincronização ao vincular/iniciar, ao voltar ao primeiro plano, após edição/importação, manualmente e a cada 5 minutos enquanto o app estiver em primeiro plano. Edições rápidas são serializadas. Uma confirmação antiga não confirma edição nova; o snapshot atual é reenviado. Falhas não desfazem escolhas locais. Arquivo local corrompido não publica automaticamente os padrões sobre o estado anterior; é necessária nova escolha salva para recuperar a gravação.

## Catálogo de IDs

| Grupo | ID | Nome na MFD |
|---|---|---|
| menus | lighting | Iluminação |
| menus | batteries | Baterias |
| menus | climate | Climatização |
| menus | tanks | Tanques |
| menus | pumps | Bombas |
| menus | anchor | Âncora |
| menus | routes | Mapa |
| menus | weather | Previsão do tempo |
| menus | alarms | Alarmes |
| menus | io | Entradas e saídas |
| menus | settings | Ajustes — obrigatório |
| indicators | service_battery | Bateria de serviço |
| indicators | fresh_water | Água doce |
| indicators | lighting | Iluminação |
| indicators | anchor | Amarra |

## Trabalho para o contexto da plataforma

1. Criar armazenamento e endpoints authenticated HMI acima, respeitando isolamento por equipamento/empresa e documentos desired/reported independentes.
2. Criar editor web com o mesmo catálogo e trava de Ajustes, salvar apenas desired e gerar revisão web.
3. Mostrar reported como estado efetivo, revisão, instalação e data de recebimento do servidor; diferenciar edição web pendente de aplicação na MFD.
4. Validar com testes: tokens de empresas distintas, duas telas do mesmo barco, revisão repetida, envio antigo, novo installation_id, layout inválido, ausência de desired, reported sem alterar desired e confirmação com eco completo.
5. Teste conjunto: mudar uma opção na MFD → reported reflete; mudar desired no portal → MFD permanece igual; clicar botão na MFD → aplica desired e novo reported confirma; voltar a editar local → nova edição permanece após reiniciar e sincronizar.

## Fontes e validação

- `lib/layout/models.dart`: esquema e IDs.
- `lib/layout/store.dart`: persistência atômica.
- `lib/layout/transport.dart`: contrato HTTP efetivamente usado.
- `lib/layout/controller.dart`: prioridade, filas e confirmação.
- `lib/layout/widgets.dart`: tela de preferências.
- Integração: `lib/main.dart`, `lib/features/home/` e `lib/preview/system_pages.dart`.
- `test/layout/`: testes de persistência, conflitos, HTTP e visibilidade.
- `docs/validacao-layout-0.9.0.md`: evidências, APK, hash e limitações verificadas na bancada.

Este handoff não contém credenciais. Usar o mecanismo existente de provisionamento de equipamentos da plataforma.


---

## Status da plataforma (04/10/2026) — IMPLEMENTADO na dev

Contrato completo no ar em `https://api-dev.marinetcs.com/api/v1`
(commits api `#391`, web idem; migração 113):

- `GET /hmi/menu-layout` e `PUT /hmi/menu-layout/reported` com token de
  equipamento; GET sem layout responde 200 com nulls; PUT ecoa o
  snapshot persistido (nunca 204/ok).
- Regras de concorrência provadas por bateria de testes na dev (9/9):
  idempotência de revisão idêntica; 409 para revisão menor, revisão
  igual com conteúdo diferente e instalação aposentada; instalação
  nova aposenta a anterior; `menus.settings=false` leva 422.
- `PUT reported` comprovadamente NÃO toca o `desired` (e vice-versa).
- Portal: **Gerenciar → Dispositivos → ⋯ → "Layout da MFD"** — editor
  do `desired` (catálogo do handoff, Ajustes travado; salvar gira
  `web_revision` opaca) ao lado do `reported` somente-leitura
  (revisão local, instalação, data, revisão web importada) com selo
  "Difere do preparado" quando divergem.

A MFD 0.9.0 da bancada, apontada para a dev, deve parar de exibir
"recurso indisponível" na próxima sincronização. O teste conjunto da
seção "Trabalho para o contexto da plataforma" (item 5) está pronto
para rodar com a placa ligada.
