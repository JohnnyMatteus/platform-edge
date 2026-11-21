# ADR 0008: SLOs da borda com alertas de burn rate em múltiplas janelas

- Status: Aceito
- Data: 2026-11-21

## Contexto

O gateway é o ponto por onde passa todo o tráfego dos produtos. Alertar por limiar fixo ("5xx > 1%") gera ruído em picos curtos e demora em degradações lentas. Além disso, 401, 403 e 429 são respostas corretas das políticas e não podem ser contadas como falha.

## Decisão

- Dois SLOs em janela de 30 dias, medidos no gateway:
  - **Disponibilidade**: 99,9% das requisições sem 5xx.
  - **Latência**: 99% das requisições respondidas em até 400 ms (bucket do histograma do Kong).
- Regras de gravação para as razões em 5m, 30m, 1h e 6h.
- Alertas por **burn rate em múltiplas janelas**: page com 14,4x em 1h e 5m; ticket com 6x em 6h e 30m.
- Alertas de política separados (`EdgeAuthFailuresSpike`, `EdgeForbiddenSpike`, `EdgeClientRateLimited`) e de dependência (`EdgeGatewayDown`, `KeycloakDown`).
- Regras versionadas e cobertas por `promtool test rules`, incluindo o teste de que negações de política não consomem orçamento.

## Consequências

- Page só quando o orçamento do mês está realmente em risco; degradações lentas viram ticket.
- A janela curta (5m) faz o alerta parar logo depois da correção.
- O SLO mede o gateway, não a experiência do usuário no navegador; medição sintética fica para depois.
- Com pouco tráfego (ambiente local), as razões oscilam muito; os limiares fazem sentido em produção.

## Alternativas consideradas

- **Limiar fixo de taxa de erro**: simples, ruidoso.
- **Uma única janela de burn rate**: ou demora para disparar ou dispara em picos curtos.
- **Sloth ou Pyrra para gerar as regras**: bons geradores; com dois SLOs, escrever as regras à mão e testá-las é mais didático e sem dependência a mais.
