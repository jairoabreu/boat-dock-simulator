# Resposta — papéis novos implementados na plataforma

**Data:** 04/08/2026 · **De:** plataforma · **Para:** firmware da tela 10.1"
**Referência:** `HANDOFF-prioridade-papeis-novos.md`

> **Resumo em uma linha:** os três papéis estão no ar no dev, na ordem que
> vocês pediram — e a bancada JÁ TEM um canal de cada para vocês verem
> chegar sem esperar ninguém.

## 1. O que o `/hmi/config` emite desde hoje

| Papel | Estado | Observações |
|---|---|---|
| `do_role: "hvac_power"` | ✅ | sem campos próprios — zona casa pela Área, como o §2.3 pede |
| `ai_role: "humidity"` | ✅ | contrato imposto: `unit='%'`, escala 0–100 (validator 422 + CHECK no banco) |
| `di_role: "flood_sensor"` | ✅ | `invert` respeitado; ver §2 sobre o lado servidor |
| `bilge_level` | ❌ não implementado | conforme a retirada de vocês — e ficou FORA do vocabulário do banco |

**Na bancada agora** (módulo `2606200006`, nó 0x42): `do5` = hvac_power,
`ai6` = humidity, `di11` = flood_sensor — rotulados "(teste)". Devem
aparecer na tela no próximo poll. Editem/apaguem à vontade pela UI; o do5
não está em nenhuma Área ainda, então a aba Ar só monta zona depois que
alguém o mover para uma.

## 2. A notificação de inundação que vocês sugeriram — feita

Worker novo (`flood_detector`), separado do de bomba de porão, porque o
problema é outro:

- **tick de 10 s** (não 30) — aqui cada minuto conta;
- dispara por **ESTADO**, não por janela: boia alta ativa = alarme;
- **re-alerta enquanto persistir**, a cada cooldown (15 min default) —
  inundação em curso não vira um único aviso perdido de madrugada;
- leitura do snapshot com mais de 5 min é estado **desconhecido**: não
  alarma com dado velho, nem cala um alarme real por módulo fora do ar;
- `invert` da fiação NA/NF respeitado, igual ao contrato de vocês;
- alerta persistido (`kind='flood.high_water'`) + push/e-mail/WhatsApp
  aos usuários da empresa.

Testado com boia simulada: alerta no banco em <25 s da ativação.

A config fica no mesmo campo de alarme da DI (`bilge_alarm`:
`cooldown_min`, `notify_company_users`, `extra_phones/emails`) — herança
de nome, semanticamente é "a config de alarme da DI".

## 3. Sobre a nota do 304 de vocês

Registrada — e o comportamento de vocês está correto: só mandar
`If-None-Match` quando há cache local é exatamente como deve ser, e o
servidor sempre responde 200 cheio quando o header não vem. Nada a mudar
de nenhum dos lados.

## 4. Fora do escopo desta rodada

Setpoint/modo/ventilador do ar (§3 do handoff de climatização) continua
como estava: o `hvac_power` liga a energia da zona; o resto é conversa de
contrato ainda aberta.
