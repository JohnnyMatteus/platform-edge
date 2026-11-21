# ADR 0003: Autorização por papel num plugin próprio, com negação por padrão

- Status: Aceito
- Data: 2026-11-21

## Contexto

Cada rota exige papéis diferentes: ler pagamentos exige `payments.read`, criar exige `payments.write`, a área administrativa dos estúdios exige `studios.admin`. Os papéis vêm do Keycloak em `realm_access.roles`. O Kong OSS não autoriza por claim do token: o plugin `acl` trabalha com grupos de consumer, que aqui representam clients, não usuários.

Também é preciso evitar o erro mais comum de gateways: uma rota nova publicada sem política fica aberta para qualquer token válido.

## Decisão

Escrever o plugin **`token-policy`** (`gateway/plugins/kong/plugins/token-policy/`):

- `policy.lua` é uma função pura `evaluate(claims, conf)` que confere issuer, audiência e papéis (`match: any` ou `all`, caminho da claim configurável). Não depende do Kong e é testada com `luajit`.
- `handler.lua` lê o token que o plugin `jwt` já autenticou, chama a política e devolve **401** para token não confiável (issuer ou audiência) e **403** para papel insuficiente.
- Prioridade 1000: roda depois do `jwt` (1450) e antes do `rate-limiting` (910), então requisição negada não consome cota.
- Falha fechada: sem token autenticado pelo `jwt`, devolve 401 (protege contra erro de configuração).
- Remove `X-Authenticated-Subject` vindo do cliente e o preenche com o `sub` do token, para o upstream confiar nesse cabeçalho.
- **Negação por padrão**: cada serviço declara `token-policy` exigindo o papel sentinela `edge.deny-by-default`, que ninguém tem. Cada rota sobrescreve com seus papéis. Rota sem política explícita recebe 403. A rota `payments-refunds` existe para provar isso nos smoke tests.

## Consequências

- Papéis por rota ficam visíveis no `kong.yaml`, revisáveis em PR.
- A política tem 17 testes unitários (casos de borda de claims malformadas) e é coberta de ponta a ponta pelos smoke tests.
- Mais um componente para manter quando o Kong mudar de versão; o acoplamento é pequeno (`kong.ctx.shared`, `jwt_parser`, `kong.response`).
- A autorização no gateway é grossa (rota e papel). Autorização fina, como "este instrutor só vê o próprio estúdio", continua no upstream, que recebe o `sub` confiável.

## Alternativas consideradas

- **Plugin `acl` com grupos**: autoriza o client, não o usuário; não atende "por papel".
- **`pre-function` com Lua inline no YAML**: funciona, mas o código fica sem testes e espalhado pela configuração.
- **OPA como sidecar (plugin OPA é Enterprise) ou ext_authz**: política em Rego é mais expressiva, mas adiciona uma chamada de rede por requisição e um componente a mais para uma regra que hoje é uma interseção de conjuntos.
- **Autorizar só nos upstreams**: cada serviço reimplementaria a mesma checagem, e um serviço esquecido ficaria exposto.
