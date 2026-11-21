# Hardening OWASP

Mapeamento das medidas da plataforma de entrada contra o **OWASP API Security Top 10 (2023)**, com o que já está implementado, onde verificar e o que falta. A borda não resolve tudo sozinha: alguns itens são responsabilidade dos serviços, e isso está explícito.

## API Security Top 10 (2023)

| Risco | O que a borda faz | Onde verificar | Fica com o upstream / próximos passos |
| --- | --- | --- | --- |
| **API1 Broken Object Level Authorization** | Propaga `X-Authenticated-Subject` confiável (removido da requisição do cliente e preenchido com o `sub` do token) para o serviço decidir por objeto | `token-policy/handler.lua`; `TestUpstreamReceivesTrustedIdentity` | A checagem por objeto (este estúdio é deste tenant?) é do saas-multitenant |
| **API2 Broken Authentication** | JWT RS256 validado localmente; `exp` obrigatório; vida máxima de 15 min; `iss` e `aud` conferidos; client desconhecido rejeitado; JWT só no cabeçalho (sem query string nem cookie); força bruta bloqueada no Keycloak; PKCE na SPA | `kong.yaml` (plugin `jwt`), `policy.lua`, `realm-edge.json`; `TestAuthentication` (9 casos) | Rotação automática da chave via JWKS |
| **API3 Broken Object Property Level Authorization** | Fora do alcance do gateway (não inspeciona corpo) | | Serialização com lista de campos permitidos nos serviços |
| **API4 Unrestricted Resource Consumption** | Rate limit por client e rota, por IP na rota anônima; limite de payload global de 1 MB e 16 KB na criação de pagamento; timeouts de conexão, leitura e escrita por serviço; sem retry no POST de pagamento | `kong.yaml`; `TestRateLimitPerClientAndRoute`, `TestPayloadLimit` | `policy: redis` com várias réplicas; proteção volumétrica na CDN/WAF |
| **API5 Broken Function Level Authorization** | Papel exigido por rota e por método; **negação por padrão** em cada serviço; área administrativa com papel próprio | `kong.yaml`, ADR 0003; `TestAuthorizationByRoleAndRoute` | |
| **API6 Unrestricted Access to Sensitive Business Flows** | Cota baixa na criação de pagamento (5/min por client) e cota contratada por parceiro | `kong.yaml` | Detecção de abuso por padrão de uso (antifraude) |
| **API7 Server Side Request Forgery** | Upstreams fixos na configuração declarativa; o cliente não escolhe destino; NetworkPolicy no chart limita o egress a DNS, OTLP e namespaces de upstream | `kong.yaml`, `charts/edge-gateway/templates/networkpolicy.yaml` | |
| **API8 Security Misconfiguration** | Admin API do Kong só em `127.0.0.1`; cabeçalhos `Server`, `Via` e latências removidos; cabeçalhos de segurança (`HSTS`, `nosniff`, `X-Frame-Options`, `Referrer-Policy`, `Cache-Control: no-store`); CORS com origem explícita e sem credenciais; container não-root, filesystem somente leitura, `no-new-privileges`, capabilities removidas; schema do chart proíbe desligar o `securityContext` | `gateway/Dockerfile`, `kong.yaml`, `values.schema.json`; `TestSecurityHeaders`, `TestCORS` | TLS terminado no Ingress (o chart exige `tlsSecretName`); mTLS até o upstream |
| **API9 Improper Inventory Management** | Toda rota existe no `kong.yaml` versionado; rota fora do arquivo não existe (404); versão no caminho (`/v1`) | `kong.yaml` | Gerar inventário/OpenAPI a partir da configuração |
| **API10 Unsafe Consumption of APIs** | Fora do escopo do gateway de entrada | | Validação de respostas de terceiros nos serviços |

## Segredos (OWASP Top 10 A02 e A07)

- Nenhum segredo real no repositório. Valores locais têm prefixo `dev-only-`, inclusive o par RSA do realm (`keycloak/dev-keys/`).
- `.env` no `.gitignore`; `.env.example` versionado com valores dev.
- Segredos de clients gerados pelo Keycloak vão para o Vault via Terraform, sem cópia manual (ADR 0006).
- Políticas do Vault de menor privilégio: o gateway só lê `edge/data/gateway/*`.
- KV com check-and-set para evitar sobrescrita acidental; audit device habilitado.
- O log JSON do Kong (`file-log`) redige `Authorization` e `Proxy-Authorization` por padrão.

## Logs e monitoramento (OWASP Top 10 A09)

- Log JSON por requisição com consumer, rota, status e latências.
- Negações do `token-policy` são logadas com motivo (`issuer_not_allowed`, `audience_not_allowed`, `missing_role`) e client, sem o token.
- Alertas de picos de 401 (credential stuffing ou chave desatualizada) e de 403 por rota (papel removido ou default-deny).

## Checklist para uma rota nova

1. Rota com método explícito e caminho versionado.
2. `token-policy` com os papéis mínimos (ou ficar de propósito no default-deny).
3. `rate-limiting` com cota justificada pela capacidade do upstream.
4. `request-size-limiting` mais restritivo se o corpo esperado é pequeno.
5. `retries: 0` no serviço se a operação não é idempotente.
6. Caso no smoke test para 401, 403 e 200.
