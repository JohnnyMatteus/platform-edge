## O que muda

<!-- Uma ou duas frases sobre o problema e a solução. -->

## Tipo de mudança

- [ ] Política de borda (rota, JWT, papel, rate limit, CORS, payload)
- [ ] Identidade ou segredos (Keycloak, Vault, Terraform)
- [ ] Deploy (Helm) ou CI
- [ ] Observabilidade (métricas, SLOs, alertas, dashboards)
- [ ] Documentação

## Checklist

- [ ] `make ci` passa localmente
- [ ] `make up && make smoke` passa quando a mudança toca o gateway ou o realm
- [ ] Rota nova tem `token-policy` explícita (ou fica de propósito no default-deny)
- [ ] Rate limit da rota nova foi definido e justificado
- [ ] Nenhum segredo real; valores de exemplo marcados como `dev-only`
- [ ] ADR criado ou atualizado se houve decisão de arquitetura
- [ ] Roteiros e runbooks atualizados se o comportamento das políticas mudou

## Como validar

<!-- Comandos ou requisições que provam a mudança. -->
