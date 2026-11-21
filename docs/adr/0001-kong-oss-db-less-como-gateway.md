# ADR 0001: Kong OSS em modo DB-less como gateway

- Status: Aceito
- Data: 2026-11-21

## Contexto

A plataforma de entrada fica na frente do processador de pagamentos (payments-events-go) e do SaaS de estúdios (saas-multitenant). O núcleo do projeto são as políticas de autenticação e de rate limit, e os requisitos explícitos são:

- validar JWT emitido pelo Keycloak;
- autorizar por papel e por rota;
- limitar por cliente e por rota, devolvendo 429 com cabeçalhos que o cliente consiga usar para se ajustar;
- CORS, limite de payload, métricas Prometheus e traces OpenTelemetry;
- configuração versionada como código, sem estado escondido num banco.

Os dois candidatos do catálogo eram KrakenD CE e Kong OSS.

## Decisão

Usar **Kong OSS 3.9 em modo DB-less**, com toda a configuração num `kong.yaml` declarativo (`gateway/declarative/kong.yaml`) embutido numa imagem própria junto com o plugin `token-policy` (ADR 0003).

O que pesou:

| Requisito | Kong OSS | KrakenD CE |
| --- | --- | --- |
| 429 com cabeçalhos | `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` e `Retry-After` nativos | Responde 429 sem cabeçalhos de cota |
| Limite por cliente | `limit_by: consumer`, e um plugin no par consumer + rota dá cota contratada por cliente | Por IP ou por um cabeçalho arbitrário; amarrar ao client do token exige contorno |
| Papel por rota | Não tem na versão OSS: exige plugin | Nativo (`roles` no validador JWT) |
| JWKS | Não tem na versão OSS: chave pública por credencial | Nativo |
| Extensão | Plugins Lua com PDK estável e testável | Plugins Go compilados contra a versão exata do binário |
| Observabilidade | Plugins `prometheus` e `opentelemetry` no OSS | Bom suporte a OpenTelemetry |

O KrakenD ganha em JWKS e papéis nativos; o Kong ganha no rate limit, que é metade do núcleo e onde o contrato com o cliente (cabeçalhos, cota por cliente) é o que importa. Os buracos do Kong OSS (papéis e JWKS) se resolvem com um plugin pequeno e com a decisão do ADR 0002; os buracos do KrakenD no rate limit exigiriam um plugin Go acoplado à versão do binário.

## Consequências

- Gateway sem banco: a configuração é imutável por release, o rollback é trocar a imagem e não há drift entre nós.
- Toda mudança de política passa por PR e pelo CI (`kong config parse` e smoke tests).
- O rate limit com `policy: local` conta por nó (ADR 0004).
- Mantemos um plugin Lua próprio, com testes unitários e de ponta a ponta.
- Recursos de Kong Enterprise (OIDC, rate limit avançado, OPA) ficam fora; se um dia forem necessários, a migração é de plugin, não de gateway.

## Alternativas consideradas

- **KrakenD CE**: descrito acima. Seria a escolha se o núcleo fosse só autenticação.
- **Kong com banco (PostgreSQL) e Admin API**: permite mudar rotas em tempo real, mas cria estado fora do Git e um banco a mais para operar.
- **Envoy + ext_authz**: muito flexível, porém exigiria escrever o rate limit service e toda a camada de configuração; custo alto para uma fundação.
- **NGINX puro com Lua (OpenResty)**: é o que o Kong já empacota, sem o modelo de plugins e a configuração declarativa.
