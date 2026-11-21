# Keycloak de desenvolvimento

`realm-edge.json` é importado pelo `docker compose` (`start-dev --import-realm`) e descreve o realm fictício `edge`:

| Tipo | Itens |
| --- | --- |
| Papéis de realm | `payments.read`, `payments.write`, `studios.read`, `studios.admin` |
| Clients | `studio-portal` (SPA pública, PKCE), `payments-ops` (confidencial, password grant só em dev), `partner-batch` (service account, client credentials) |
| Usuários | `ana.operadora` (pagamentos), `bruno.instrutor` (leitura de estúdios), `carla.gestora` (admin de estúdios), `diego.visitante` (sem papéis) |

Todos os clients têm um mapper de audiência que adiciona `edge-gateway` em `aud`, conferido pelo plugin `token-policy`.

## Credenciais (DEV ONLY)

- Senha de todos os usuários: `dev-only-change-me`.
- Segredos dos clients: `dev-only-payments-ops-secret` e `dev-only-partner-batch-secret`.
- Console de administração: `admin` / `dev-only-change-me` em http://localhost:8080.

## Chave de assinatura (`dev-keys/`)

O realm assina tokens com um par RSA gerado **apenas para este repositório**. Ele é fixo para que o gateway valide os tokens sem depender do Keycloak em tempo de execução (ver [ADR 0002](../docs/adr/0002-jwt-com-chave-publica-por-consumer.md)). A chave privada aparece em `dev-keys/` e embutida no realm; ela não protege nada fora do ambiente local.

Em ambientes reais, o realm é criado pelo Terraform (`terraform/modules/keycloak-realm`) com chaves geradas pelo próprio Keycloak, e a chave pública chega ao gateway pelo JWKS.

Para trocar o par local: gere um novo par com `openssl`, atualize `components` em `realm-edge.json` e os três `rsa_public_key` em `gateway/declarative/kong.yaml`.
