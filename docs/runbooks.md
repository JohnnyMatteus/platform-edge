# Runbooks

Primeiros passos para cada alerta. Em todos: abrir o dashboard "Edge Gateway: SLOs e políticas" no Grafana e buscar traces do serviço `edge-gateway` no Jaeger pelo `X-Kong-Request-Id`.

## EdgeAvailabilityBudgetBurnFast

1. Painel "Respostas por código": os 5xx vêm do Kong (`source="kong"`, ex.: 502/504) ou do upstream (`source="service"`)?
2. 502/503 do Kong: upstream fora ou sem alvo saudável. Conferir health checks dos upstreams e logs do serviço.
3. 504: timeout. Conferir latência do upstream no painel de latência e nos traces.
4. Se começou após um deploy do gateway: rollback para a imagem anterior (configuração é imutável por imagem).

## EdgeAvailabilityBudgetBurnSlow

Mesmo diagnóstico, sem urgência. Abrir ticket com a rota e o código predominantes.

## EdgeLatencyBudgetBurnFast

1. Painel "Latência por rota": uma rota ou todas?
2. Uma rota: provavelmente o upstream. Traces no Jaeger mostram o tempo no upstream.
3. Todas: o próprio gateway (CPU, réplicas). Conferir HPA e `kong_kong_latency_ms`.

## EdgeLatencyBudgetBurnSlow

Mesmo diagnóstico; abrir ticket.

## EdgeGatewayDown

1. `kubectl get pods -l app.kubernetes.io/name=edge-gateway` (ou `make ps` local).
2. Pod em CrashLoop: `kong config parse` falhou? Ver logs; a configuração inválida deveria ter sido barrada no CI.
3. Pods ok mas sem métricas: NetworkPolicy do namespace de monitoramento.

## EdgeAuthFailuresSpike

1. Concentrado em um client (`consumer=""` não ajuda; ver logs do Kong com a mensagem do `jwt`)?
2. `Invalid signature` em massa: a chave do realm mudou e o gateway não foi atualizado. Publicar a chave nova no `kong.yaml` (ver roteiro de autenticação, rotação).
3. `token expired` em massa: relógio dessincronizado ou cliente sem renovar token.
4. Muitos IPs, tokens aleatórios: tentativa de abuso; acionar bloqueio na CDN/WAF.

## EdgeForbiddenSpike

1. Qual rota? Rota nova caindo no default-deny: faltou `token-policy` na rota.
2. Rota antiga: papel removido ou renomeado no Keycloak. Conferir o realm (Terraform) e os logs `token-policy denied reason=missing_role`.

## EdgeClientRateLimited

1. Qual client e rota? É tráfego legítimo crescendo ou laço com bug?
2. Bug: avisar o dono do client; a cota está protegendo o upstream.
3. Crescimento legítimo: revisar a cota com a capacidade do upstream e, se for parceiro, o contrato. Cota específica vai num plugin consumer + rota.

## KeycloakDown

1. Impacto: novos logins e renovações falham; tokens emitidos valem até expirar (5 min). O gateway segue funcionando.
2. Ver logs e health (`/health/ready` na porta 9000).
3. Se a indisponibilidade passar de alguns minutos, os usuários começam a ser deslogados; comunicar.
