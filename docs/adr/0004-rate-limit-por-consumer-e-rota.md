# ADR 0004: Rate limit por consumer e por rota, com contagem local

- Status: Aceito
- Data: 2026-11-21

## Contexto

O rate limit protege os upstreams e reparte capacidade entre clientes. Os requisitos:

- a cota é **por cliente e por rota**: estourar a escrita de pagamentos não pode bloquear a leitura;
- parceiros podem ter cota contratada diferente;
- a resposta de estouro é 429 com cabeçalhos para o cliente saber quanto esperar;
- rotas anônimas precisam de limite também.

## Decisão

- Plugin `rate-limiting` **em cada rota**, com `limit_by: consumer`. Como o consumer é o client do Keycloak (ADR 0002), a contagem fica naturalmente por cliente e por rota.
- **Cota por cliente** com um plugin no par consumer + rota (`partner-batch` em `payments-write`: 20/min contra 5/min do padrão). O Kong dá precedência ao plugin mais específico.
- Rota anônima (`studios-public-schedule`) com `limit_by: ip`.
- Janela de um minuto, `policy: local` (contador em memória de cada nó), `fault_tolerant: true`.
- Cabeçalhos sempre visíveis (`hide_client_headers: false`) e expostos pelo CORS: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` e, no 429, `Retry-After`.
- O rate limit roda depois da autorização: 401 e 403 não consomem cota.

| Rota | Limite padrão | Observação |
| --- | --- | --- |
| `payments-read` | 60/min por client | |
| `payments-write` | 5/min por client | `partner-batch`: 20/min |
| `studios-read` | 120/min por client | |
| `studios-admin` | 30/min por client | |
| `studios-public-schedule` | 30/min por IP | sem token |

## Consequências

- Sem dependência externa no caminho da requisição.
- Com N réplicas, o limite efetivo é até N vezes o configurado, porque cada nó conta sozinho. Com o balanceamento uniforme, a imprecisão é previsível; para cotas contratuais exatas é preciso `policy: redis` (próximos passos).
- Janela fixa permite rajada de até 2x na virada do minuto. Aceitável para proteção; para cobrança por uso, não.
- Requisições de usuários diferentes do mesmo client dividem a cota do client. É o comportamento desejado para proteger o upstream; limite por usuário (`sub`) fica para depois.

## Alternativas consideradas

- **`policy: redis`**: contagem global e exata, com Redis no caminho crítico. Vira padrão quando o gateway tiver mais de uma réplica em produção.
- **Limite por IP em tudo**: injusto atrás de NAT corporativo e fácil de contornar com IPs rotativos.
- **Limite global por serviço**: protege o upstream, mas um cliente barulhento derruba todos os outros.
- **Plugin `rate-limiting-advanced` (janela deslizante)**: Enterprise.
