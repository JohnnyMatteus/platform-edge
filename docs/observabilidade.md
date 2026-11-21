# Observabilidade

| Sinal | Origem | Destino local | Como ver |
| --- | --- | --- | --- |
| Métricas | Plugin `prometheus` do Kong (porta 8100), Keycloak (porta 9000) | Prometheus | http://localhost:9090 |
| Dashboards | JSON provisionado em `observability/grafana/dashboards/` | Grafana | http://localhost:3000 (anônimo como Viewer; admin `admin` / `dev-only-change-me`) |
| Traces | Plugin `opentelemetry` do Kong (OTLP/HTTP), contexto W3C propagado ao upstream | Jaeger | http://localhost:16686, serviço `edge-gateway` |
| Logs | `file-log` do Kong em JSON no stdout; stubs com `slog` JSON; Keycloak em JSON | stdout dos containers | `make logs SERVICE=gateway` |

## Correlação

- Toda resposta tem `X-Kong-Request-Id`, também enviado ao upstream e presente no log JSON.
- O Kong injeta `traceparent` no upstream; os stubs registram o `trace_id` no log. Do log do stub dá para abrir o trace no Jaeger.

## Métricas principais

| Métrica | Labels | Uso |
| --- | --- | --- |
| `kong_http_requests_total` | `service`, `route`, `code`, `source`, `consumer` | SLO de disponibilidade, negações de política, 429 por client |
| `kong_request_latency_ms_bucket` | `service`, `route`, `le` | SLO de latência, percentis |
| `kong_upstream_latency_ms_bucket` | `service`, `route`, `le` | Separar tempo do upstream do tempo do gateway |
| `kong_kong_latency_ms_bucket` | `service`, `route`, `le` | Custo dos plugins |
| `up` | `job` | Gateway e Keycloak no ar |

`per_consumer: true` aumenta a cardinalidade (client x rota x código). Com três clients é irrelevante; com centenas de parceiros, vale desligar e usar logs para a visão por client.

## SLOs

Ver [slos.md](slos.md).
