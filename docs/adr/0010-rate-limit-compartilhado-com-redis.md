# ADR 0010: Rate limit compartilhado com Redis; JWKS fora do gateway DB-less

- Status: Aceito (revisa a decisão de contagem local do [ADR 0004](0004-rate-limit-por-consumer-e-rota.md))
- Data: 2026-11-21

## Contexto

Com `policy: local` cada nó do Kong conta sozinho: com N réplicas o limite efetivo chega a N vezes o configurado, o que não serve para cota contratual (`partner-batch`, 20/min). O chart Helm já sobe 2 a 6 réplicas.

Havia também um item pendente do [ADR 0002](0002-jwt-com-chave-publica-por-consumer.md): obter a chave de assinatura pelo JWKS do Keycloak em vez de colar a chave pública no `kong.yaml`.

## Decisão

### Rate limit

- Todas as instâncias do plugin `rate-limiting` usam `policy: redis`, com o endereço definido uma vez (âncora YAML `ratelimit_redis`: host `redis`, porta 6379, timeout de 200 ms).
- `redis:7.4.6-alpine` entra no profile `core` do compose, com healthcheck, volume nomeado e sem persistência (`--save ""`, `--appendonly no`): perder a contagem num restart só zera a janela de 1 minuto. `maxmemory` de 64 MB com `volatile-ttl`.
- `fault_tolerant: true` continua: se o Redis cair ou passar de 200 ms, a requisição passa sem limite (prefere-se disponibilidade a bloquear tráfego legítimo). O alerta de Redis fora do ar fica como próximo passo de observabilidade.
- A contagem é comum às instâncias porque o Kong em DB-less gera os ids de rota e consumer de forma determinística a partir da configuração; a chave no Redis usa esses ids. Todas as réplicas carregam o mesmo `kong.yaml`.
- O compose sobe uma segunda instância (`gateway-replica`, porta 8001) só para provar isso. O smoke test `TestRateLimitIsSharedAcrossGatewayInstances` alterna chamadas entre as duas e exige que `RateLimit-Remaining` caia de um em um; com `policy: local` esse teste falharia.
- Helm: o `NetworkPolicy` libera o egress para o Redis (`networkPolicy.redis`). O host real vem do `kong.yaml` do ambiente. Terraform: o endereço fica em `gateway/rate-limit-redis` no Vault, na policy `edge-gateway`.

### JWKS do Keycloak: não implementado

Não é viável no Kong OSS em DB-less:

- o plugin `jwt` valida com a chave pública guardada na credencial do consumer; não busca JWKS (`openid-connect` é Enterprise);
- em DB-less a configuração é imutável em runtime e não há Admin API de escrita, então um processo não consegue "atualizar a credencial" depois do boot;
- um plugin Lua próprio teria de buscar o JWKS, cachear, escolher a chave por `kid` e verificar a assinatura RS256, reimplementando o que o `jwt` já faz.

Mantém-se o ADR 0002. A rotação continua por configuração: publicar a chave nova no `kong.yaml` antes de o Keycloak passar a assinar com ela e fazer rolling update das réplicas. O caminho recomendado, quando a rotação importar, é um job de CI que lê o JWKS e gera o `jwt_secrets`.

## Consequências

- Cota exata e global por consumer e rota, independente do número de réplicas.
- Uma ida ao Redis por requisição com limite (sub-milissegundo na mesma rede) e um componente a mais para operar.
- Redis único é ponto único de falha do limite, não do tráfego (`fault_tolerant`). Alta disponibilidade (Sentinel/ElastiCache) é evolução.
- Janela fixa de 1 minuto permanece (a janela deslizante é Enterprise).

## Alternativas consideradas

- **Manter `policy: local`**: sem dependência, mas imprecisa com réplicas.
- **`policy: cluster`**: exige banco do Kong, incompatível com DB-less.
- **Afinidade de sessão por consumer no balanceador**: acopla o limite à topologia e quebra em failover.
- **Plugin Lua com JWKS**: ver acima.
