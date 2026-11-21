# Padrões de projeto e SOLID neste repositório

O projeto é, sobretudo, configuração (Kong, Helm, Terraform) com um plugin Lua pequeno e um stub em Go. Só estão listados padrões que o código realmente tem; onde um padrão clássico não cabe, está dito.

## Padrões

### Núcleo puro e adaptador (portas e adaptadores)

- **Onde:** [`policy.lua`](../../gateway/plugins/kong/plugins/token-policy/policy.lua#L79) (`evaluate`) e [`handler.lua`](../../gateway/plugins/kong/plugins/token-policy/handler.lua#L14) (`access`).
- **Problema:** decidir "pode passar?" sem depender de `kong.*`, para testar com `luajit` sem subir o Kong.
- **Como:** `evaluate(claims, conf)` recebe tabelas e devolve uma decisão; o handler adapta o Kong (token do contexto, `kong.response.exit`, cabeçalhos) à função pura. Testes em [`policy_spec.lua`](../../gateway/spec/policy_spec.lua).
- **Trade-off:** uma camada a mais para um plugin de ~40 linhas de lógica; compensa porque a regra de autorização é a parte crítica.

### Chain of Responsibility (pipeline de plugins do Kong)

- **Onde:** [`kong.yaml`](../../gateway/declarative/kong.yaml) (plugins por serviço e rota) e [`handler.lua`](../../gateway/plugins/kong/plugins/token-policy/handler.lua#L10) (`PRIORITY = 1000`).
- **Problema:** autenticar, autorizar e só então contar cota, para que 401 e 403 não consumam rate limit.
- **Como:** o Kong ordena os plugins por prioridade (cors, jwt, token-policy, rate-limiting); cada elo pode encerrar a requisição.
- **Trade-off:** a ordem está implícita nas prioridades do Kong, não no código nosso; por isso o smoke test confere que negadas não gastam cota.

### Strategy (modo de combinar papéis)

- **Onde:** [`policy.lua`](../../gateway/plugins/kong/plugins/token-policy/policy.lua#L54) (`roles_satisfied`) e [`schema.lua`](../../gateway/plugins/kong/plugins/token-policy/schema.lua#L21) (`match`).
- **Problema:** rotas pedem "qualquer um dos papéis" ou "todos".
- **Como:** o valor `any` ou `all` da configuração seleciona o comportamento. É uma Strategy mínima, escolhida por dado, não por classe.
- **Trade-off:** dois modos não justificam hierarquia; se surgir um terceiro (por exemplo, papel por escopo), vira tabela de funções.

### Dependency Injection do relógio (estilo Factory)

- **Onde:** [`handler.go`](../../internal/stub/handler.go#L51) (`NewHandler(service, logger, now)`).
- **Problema:** teste determinístico do campo `received_at`.
- **Trade-off:** um parâmetro a mais; sem framework de DI.

### Failover por peso no balanceador (não é um padrão clássico)

- **Onde:** [`kong.yaml`](../../gateway/declarative/kong.yaml#L232) (`upstreams`, pesos 999 e 1 com health check ativo).
- **Problema:** a borda precisa rodar sozinha (CI) e com os serviços reais.
- **Trade-off:** cerca de 0,1% do tráfego local cai no stub ([rede-portfolio](../rede-portfolio.md)); o Kong OSS não tem alvo de reserva.

### Não aplicados

Repository, Outbox, Decorator, Specification e Adapter de persistência não existem aqui: o gateway não tem banco. O rate limit em Redis é resolvido pelo plugin do Kong, configurado por dado (âncora `ratelimit_redis` em `kong.yaml`), então não há porta de cache escrita por nós.

## SOLID

| Princípio | Onde está | Observação |
| --- | --- | --- |
| **S**ingle Responsibility | `policy.lua` decide, `handler.lua` integra com o Kong, `schema.lua` valida a configuração | Três arquivos, três motivos para mudar |
| **O**pen/Closed | Rota nova com política própria é só configuração em `kong.yaml`, sem tocar no plugin; âncoras (`token_policy_base`, `ratelimit_redis`) evitam repetição | Papel novo de conta no realm, não no código |
| **L**iskov | Os stubs ([`handler.go`](../../internal/stub/handler.go#L55)) respondem ao mesmo contrato HTTP dos serviços reais (`/healthz`, `/up`, cabeçalhos propagados), então trocam de lugar nos upstreams | Vale só para o contrato que os smoke tests conferem |
| **I**nterface Segregation | `evaluate` recebe só `claims` e `conf`, não o contexto do Kong; o schema declara só os campos que a política lê | |
| **D**ependency Inversion | A política não importa `kong`; o relógio do stub é injetado; o endereço do Redis e dos upstreams vem da configuração | |
