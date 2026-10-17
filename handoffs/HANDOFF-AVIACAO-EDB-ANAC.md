# MaTel Flight como Diário de Bordo Eletrônico (eDB) aprovado pela ANAC

Levantamento de 17/10/2026. Textos oficiais baixados em `refs/anac-edb/`:
`res-773.txt` (diário de bordo), `res-458.txt` (sistemas informatizados),
`portaria-3220.txt` (modelo de referência do eDB) e `api-manual-2.0.txt`
(guia da API, v2.0 de 03/04/2025).

## 1. O que a norma pede

| Norma | O que define |
|---|---|
| **Res. ANAC 773/2025**, em vigor desde 01/01/2026 (revogou a 457/2017) | O conteúdo do diário. Físico ou digital, com integridade garantida e correções visíveis (art. 3º). Guarda por toda a vida da aeronave + 5 anos e 1 dia após o cancelamento da matrícula. O uso do meio digital precisa de pedido à ANAC (art. 4º). |
| **Res. ANAC 458/2017** (alterada pelas 511/2019 e 678/2022) | Requisitos do sistema. A segurança é demonstrada por (a) relatório de entidade certificadora (ISO 27000), (b) blockchain da ANAC ou (c) cópia de todos os dados no banco da ANAC (API). Exige também os requisitos de segurança do art. 4º. |
| **Portaria 3.220/SPO/SAR/2019** (compilada até 2024) | Modelo de referência do eDB: volumes, termos de abertura e encerramento, campos de cada etapa, situação técnica (Parte II), assinaturas, apresentação na tela e impressão (Anexo III), guarda. |
| **Guia da API v2.0** | Envio da cópia à ANAC: volumes e etapas de voo. A tripulação vai por CPF e a CIV Digital do piloto é alimentada automaticamente. |

**Atenção — via (c):** o guia v2.0 diz textualmente que "a versão atual da
API não possibilita a aplicação do Art 3º, alínea C, da Res. 458". Hoje,
portanto, a aprovação exige o **relatório de uma entidade certificadora (via
a)**. A API continua valendo para compartilhar os dados: alimenta a CIV
Digital, dispensa a Res. 219 (art. 15 da 773) e dá direito ao redutor de
penalidade da Res. 762/2024.

**Caminho para o PR-III (RBAC 91):**
1. Verificação do software no SEI: check-list da Res. 458 + relatório de conformidade da certificadora.
2. Avaliação operacional, feita em conjunto pelo desenvolvedor e pelo operador (só na primeira autorização).
3. LOA 91: carta + formulário D-144-01, sem taxa.

Os pedidos 1 e 3 podem correr no mesmo processo. Depois da aprovação, o
diário é preenchido **só** no eDB (Res. 458, art. 5º).

## 2. Lacunas do nosso diário atual

O app e a API foram feitos sobre a Res. 457.

### 2.1 Estrutura

| Requisito | Hoje | Falta |
|---|---|---|
| Volumes com termo de abertura e encerramento, número `NN/CC-MMM/AAAA` (Portaria arts. 4º–7º) | Numeração sequencial por aeronave, sem volumes | Tabela de volumes. Abertura com horas totais, pousos, ciclos de célula, horas e ciclos de motor, proprietário e operador do RAB e observações. Encerramento igual. Só um volume aberto por vez. Assinatura do operador nos termos. |
| Identificação da aeronave (773 art. 5º): fabricante, modelo, série, marcas, **proprietário(s) e operador(es)** | Fabricante, modelo e série no cadastro | Proprietário e operador (vêm do RAB; a API preenche os operadores ao abrir o volume). |
| Parte II — situação técnica (773 arts. 8º–9º; Portaria arts. 28–41) | Não existe | Última e próxima intervenção de manutenção, horas de célula até a próxima. Discrepâncias com sistema ATA 100, quem detectou (código ANAC + assinatura), ação corretiva e liberação de retorno ao serviço (mecânico, RBAC 43, código ANAC + assinatura). **Ciência assinada pelo piloto antes do voo.** |
| Aviso de inicialização (Portaria art. 11) | Não existe | Ao abrir o diário no iPad: termo de abertura + discrepâncias abertas e ações corretivas, com confirmação de leitura obrigatória antes de liberar o resto. |

### 2.2 Campos da etapa (773 art. 6º; Portaria art. 15; API `EtapaVoo`)

| Campo | Hoje | Como deve ficar |
|---|---|---|
| Tripulação | Código ANAC + função P/I/O/C/M | Código ANAC (Portaria) **e CPF** (a API identifica por CPF). Funções novas: P1, P2, I1, I2, O1, O2, O3, V1, V2, V3, C, M, X, D (Portaria 14.096/2024; API usa ids 1–14). Hora de apresentação e base contratual, se remunerada. |
| Natureza | Texto livre (privado/comercial/outro) | Código: AE, CQ, EX, NR, RE, PV, SA, TN, TR (API: 1–10, inclui aeromédico). |
| Origem e destino | ICAO ou coordenadas | ICAO. Sem ICAO: `ZZZZ` + nome do local, ou coordenadas WGS-84 `gg mm ssQ/ggg mm ssG` (Portaria art. 19). |
| Horários | Partida, decolagem, pouso e corte (UTC) | Ok. Marcar UTC (Z). |
| Tempos | Voo, noturno, IFR (decimal) | Diurno, noturno, total, **IFR real e IFR simulado** separados. Decimal no diário (art. 21); HH:MM na API. |
| Pousos e ciclos | Pousos | **Ciclos** parciais e totais; pousos totais. |
| Combustível | Texto livre | **Número inteiro na partida dos motores + unidade** (kg, L, lb, gal). |
| Pessoas a bordo | Inteiro | Ok (inclui a tripulação). |
| Carga | Texto livre | Inteiro + unidade (kg, lb). |
| Ocorrências | Texto livre | Estruturadas: data/hora, local (coordenada se em voo), classe HTSAN, AVSEC, PBSEC ou OTR, pessoas envolvidas e descrição. Só ocorrências entre o fechamento e a abertura de portas. |
| Navegação | — | Milhas e minutos de navegação (opcional; dá crédito na CIV). |
| Identificador da etapa | id interno | Indicador inequívoco (matrícula + data e hora da decolagem serve, art. 16). |

### 2.3 Assinaturas e integridade (Res. 458 art. 4º; Portaria cap. VII)

| Requisito | Hoje | Falta |
|---|---|---|
| Assinatura do piloto em comando até o fim da jornada | Confirmação no iPad + hash SHA-256 no servidor | Assinatura eletrônica individual: intenção declarada ("Assino…"), revisão do conteúdo antes, notificação depois, ligada ao registro e inalterável sem nova assinatura. |
| Criptografia assimétrica + **certificado digital ICP-Brasil ou equivalente** (art. 4º, I) | Não | Chave privada por usuário + certificado. Decisão em aberto, ver §4. |
| Assinatura do operador (773 art. 10: até 30 dias no RBAC 91) | Não | Fila do operador no site: revisar e assinar as etapas do período (API: PUT Assinatura). |
| Correção sem apagar (773 art. 3º §2º) | Correção cria nova entrada e marca a original | Ok no conceito. A correção exige nova assinatura do piloto e do operador. |
| Trilha de auditoria, backup, políticas (art. 4º, III e V) | Backup diário `pg_dump` **no mesmo servidor** | Log de auditoria imutável; backup **fora** do servidor (outra região) com teste de restauração. Políticas escritas: segurança, backup, auditoria, treinamento, equipe responsável, controle de acesso, mudança de sistema. |
| Últimos 30 dias na aeronave, funcionando sem internet (773 art. 7º §2º; Portaria art. 9º) | O diário fica no iPad | Ok. Garantir os 30 dias inteiros offline e a fila de envio. |
| Preenchimento só em solo com motor cortado, salvo EFB autorizado (Portaria art. 10) | Livre | Bloquear a edição com GS > 0 / motor ligado, ou ter autorização EFB (IS 91-002). |
| Apresentação na tela e impressão no modelo do Anexo III, cada página com a assinatura digital do operador (Portaria arts. 44–45) | Lista no app, CSV no site | Telas e PDF no layout do Anexo III, com filtro por data e cronologia. |

## 3. Plano

| Fase | Entrega | Quem |
|---|---|---|
| **A** | Modelo de dados conforme 773 + Portaria (app + API): volumes, campos novos da etapa, Parte II, aviso de inicialização, bloqueio em voo | Claude |
| **B** | Assinatura eletrônica forte (§4) + fila de assinatura do operador no site | Claude, depois da decisão do §4 |
| **C** | Integração com a API da ANAC no servidor: token SSO, volume, etapa, assinatura, correção, fila com reenvio | Claude. **Credencial temporária de homologação** pedida pela MaTel (e-mail em §5). |
| **D** | Conformidade: auditoria imutável, backup externo, telas e PDF do Anexo III, documentos de política (Res. 458 art. 4º, III/V) e check-list da Res. 458 | Claude (rascunhos); revisão da MaTel |
| **E** | Relatório da certificadora (ISO 27000) + SEI: verificação do software, avaliação operacional e LOA 91 do PR-III | MaTel |

## 4. Decisões em aberto

1. **Certificado da assinatura (Res. 458 art. 4º, I, f).** Opções:
   - certificado ICP-Brasil **em nuvem** (VIDaaS/Valid, BirdID/Soluti, NeoID/Serpro), que assina pelo celular via API — o mais prático no iPad;
   - certificado A1 de cada piloto importado no app;
   - "equivalente": chave no Secure Enclave do iPad + certificado emitido pela própria MaTel. Mais simples, mas depende da certificadora aceitar como equivalente.
2. **Quem é o "Gestor do DBE"** junto à ANAC: a pessoa jurídica dona do software (MaTel / Marine Telematics, CNPJ).
3. **CPF dos tripulantes** passa a ser guardado (exigido pela API): dado pessoal. Atualizar o termo de consentimento (LGPD) e restringir quem vê.

## 5. Pedido da credencial temporária (rascunho)

Para: dbdigital@anac.gov.br
Assunto: Solicitação de Credencial TEMPORÁRIA para a API Diário de Bordo – Homologação

Prezados,

Solicitamos credencial temporária de acesso ao ambiente de homologação da API
do Diário de Bordo Eletrônico, para o desenvolvimento da integração do
software MaTel Flight (diário de bordo eletrônico em iPad + plataforma web),
ainda em processo de adequação à Resolução nº 458/2017.

- Nome / Razão Social: [preencher]
- CNPJ: [preencher]
- Endereço: [preencher]
- Preposto: [nome] — CPF [preencher] — e-mail [preencher] — telefone/WhatsApp [preencher]

Atenciosamente,
[assinatura]
