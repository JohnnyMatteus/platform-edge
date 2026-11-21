# CLAUDE.md

Guia para sessões de agente neste repositório.

## Visão

`platform-edge` é a plataforma de entrada compartilhada do ecossistema fictício do portfólio: Kong OSS (DB-less) com políticas como código na frente do `payments-events-go` e do `saas-multitenant`, Keycloak para identidade, Vault para segredos, Terraform e Helm para provisionamento, Prometheus, Grafana e Jaeger para observabilidade. O núcleo é **autenticação/autorização** e **rate limit** (ver `docs/roteiros/`).

## Regras

- Domínio 100% fictício. Nada de nomes reais de pessoas, clientes ou empresas. E-mails só `@example.com`.
- Nenhum segredo real. Valores locais usam o prefixo `dev-only-`. `.env` nunca é versionado; mude `.env.example`.
- Docs em português do Brasil; identificadores de código, nomes de testes e chaves de configuração em inglês.
- Toda rota nova no `gateway/declarative/kong.yaml` precisa de `token-policy` explícita (ou fica de propósito no default-deny), `rate-limiting` justificado e caso nos smoke tests.
- Mudança de papel ou client vale para os dois lugares: `keycloak/realm-edge.json` e `terraform/envs/local/main.tf`.
- A chave RSA de `keycloak/dev-keys/` é DEV ONLY; se trocar, atualize o realm e os três `rsa_public_key` do `kong.yaml`.
- Decisão de arquitetura nova vira ADR em `docs/adr/` (Contexto, Decisão, Consequências, Alternativas).
- Não use `latest` em imagens. Versões ficam fixadas no `Makefile`, nos Dockerfiles e no compose.
- Commits em Conventional Commits, pequenos, com `git commit -F <arquivo>`.

## Comandos

```bash
make help              # lista tudo
make up                # rede portfolio-net + profiles core,observability (PROFILES=core para o mínimo)
make ps | make logs SERVICE=gateway | make down | make clean
make seed              # terraform apply de envs/local contra a stack
make test              # Go, Lua (luajit da imagem do Kong) e promtool
make test-integration  # smoke tests Go contra a stack (exige make up)
make lint              # gofmt/vet, kong config parse, terraform fmt/validate, helm lint, promtool check
make ci                # o que o CI roda, menos os smoke tests
```

Terraform, Helm, kubeconform, promtool e o Kong rodam por `docker run`; só Docker e Go são necessários.

## Estrutura

| Caminho | O que é |
| --- | --- |
| `gateway/declarative/kong.yaml` | Fonte da verdade das políticas de borda |
| `gateway/plugins/kong/plugins/token-policy/` | Plugin Lua: `policy.lua` (pura), `handler.lua`, `schema.lua` |
| `gateway/spec/` | Executor mínimo e testes Lua da política |
| `cmd/upstream-stub`, `internal/stub` | Stub Go que imita os upstreams e ecoa os cabeçalhos do gateway |
| `tests/smoke/` | Smoke tests (build tag `smoke`) |
| `keycloak/` | Realm exportado e chaves dev |
| `terraform/modules/{keycloak-realm,vault-edge}`, `terraform/envs/local` | IaC |
| `charts/edge-gateway/` | Chart Helm, com `ci/*.yaml` como variantes validadas |
| `observability/prometheus/rules/` | SLOs, alertas e testes `promtool` |
| `observability/grafana/` | Provisionamento e dashboard JSON |
| `init/aws/` | Bootstrap do LocalStack (profile `tools`) |
| `docs/` | Design doc, ADRs, roteiros, OWASP, SLOs, runbooks, rede do portfólio |

## Fluxo de trabalho

1. Branch a partir da `main` (`feat/...`, `fix/...`).
2. Política nova: comece pelo teste (caso em `gateway/spec/policy_spec.lua` se mexer na política pura; caso em `tests/smoke/` para o comportamento da rota).
3. `make ci` e, se tocar gateway ou realm, `make up && make test-integration`.
4. Atualize roteiros, runbooks e ADRs quando o comportamento mudar.
5. PR com o template; o CI precisa passar.

## Armadilhas conhecidas

- O `iss` dos tokens depende de `KC_HOSTNAME` (`http://localhost:8080`). Mudar a porta do Keycloak quebra o `allowed_issuers`.
- O Kong rejeita chaves de topo desconhecidas no `kong.yaml`: âncoras YAML ficam no primeiro uso.
- Rota sem `OPTIONS` em `methods` responde 404 ao preflight de CORS.
- Rate limit usa janela fixa de 1 minuto; os smoke tests toleram execuções repetidas no mesmo minuto.
- Os smoke tests conferem o eco dos stubs: rode com os projetos reais fora da `portfolio-net`.
- O `start-dev` do Keycloak refaz o build do Quarkus a cada container; em máquina carregada a subida passa de vários minutos (os healthchecks têm `start_period` e `retries` generosos por isso).
