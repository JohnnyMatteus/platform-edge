# SLOs e alertas

Regras em `observability/prometheus/rules/`, testadas com `promtool` (`make prom-test`). Decisão no [ADR 0008](adr/0008-slos-com-burn-rate-multijanela.md).

## SLOs

| SLO | SLI | Objetivo | Janela | Orçamento |
| --- | --- | --- | --- | --- |
| Disponibilidade | Requisições sem 5xx / todas as requisições (`kong_http_requests_total`) | 99,9% | 30 dias | 0,1% (cerca de 43 min de indisponibilidade total) |
| Latência | Requisições com latência total <= 400 ms / todas (`kong_request_latency_ms_bucket{le="400"}`) | 99% | 30 dias | 1% |

401, 403 e 429 são respostas corretas das políticas e contam como boas. Um teste de `promtool` garante isso.

## Alertas de SLO (burn rate em múltiplas janelas)

| Alerta | Condição | Severidade | Por quê |
| --- | --- | --- | --- |
| `EdgeAvailabilityBudgetBurnFast` | erro > 14,4 x 0,1% em 1h **e** em 5m, por 2m | page | 2% do orçamento mensal em 1 hora |
| `EdgeAvailabilityBudgetBurnSlow` | erro > 6 x 0,1% em 6h **e** em 30m, por 15m | ticket | 5% do orçamento em 6 horas |
| `EdgeLatencyBudgetBurnFast` | lentas > 14,4 x 1% em 1h e 5m | page | |
| `EdgeLatencyBudgetBurnSlow` | lentas > 6 x 1% em 6h e 30m | ticket | |

A janela longa evita alertar por pico curto; a curta faz o alerta parar logo depois da correção.

## Alertas de política e dependências

| Alerta | Condição | Severidade |
| --- | --- | --- |
| `EdgeGatewayDown` | `up{job="edge-gateway"} == 0` por 2m | page |
| `EdgeAuthFailuresSpike` | 401 > 20% com mais de 1 req/s, por 10m | ticket |
| `EdgeForbiddenSpike` | 403 > 10% numa rota com mais de 0,5 req/s, por 15m | ticket |
| `EdgeClientRateLimited` | 429 > 0,5/s para um client numa rota, por 10m | info |
| `KeycloakDown` | `up{job="keycloak"} == 0` por 5m | page |

Cada alerta aponta para uma seção do [runbook](runbooks.md).

## Testes das regras

`observability/prometheus/rules/tests/slo-edge-gateway.test.yml` cobre:

- 5% de 5xx dispara o page de disponibilidade;
- 401, 403 e 429 em volume não disparam nenhum alerta de SLO;
- 429 sustentado dispara `EdgeClientRateLimited` só para o client afetado;
- 30% de 401 dispara `EdgeAuthFailuresSpike`;
- 3% de lentidão (3x) não dispara alerta de latência; 20% dispara o page;
- gateway e Keycloak fora disparam depois do `for` configurado, e não antes.
