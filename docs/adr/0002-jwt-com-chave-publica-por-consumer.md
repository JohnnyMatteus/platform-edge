# ADR 0002: JWT validado localmente, com um consumer por client do Keycloak

- Status: Aceito
- Data: 2026-11-21

## Contexto

O gateway precisa validar tokens emitidos pelo Keycloak sem virar um ponto de acoplamento forte com ele. As opções são validar localmente (assinatura com chave pública) ou perguntar ao Keycloak a cada requisição (introspecção). Também é preciso saber **qual client** fez a chamada, porque o rate limit é por cliente (ADR 0004).

O plugin `jwt` do Kong OSS valida assinatura RS256 e `exp`, mas não busca JWKS: a chave pública é cadastrada numa credencial (`jwt_secrets`) de um consumer, e o consumer é escolhido pelo valor de uma claim (`key_claim_name`).

## Decisão

- Validar o JWT **localmente** com o plugin `jwt`, sem chamada ao Keycloak no caminho da requisição.
- Usar `key_claim_name: azp`. O Keycloak põe o client id em `azp`, então **cada client do Keycloak vira um consumer do Kong** (`studio-portal`, `payments-ops`, `partner-batch`). Um token de client desconhecido recebe 401.
- Conferir `exp` e limitar a vida útil a 15 minutos (`maximum_expiration: 900`), acima dos 5 minutos configurados no realm.
- O plugin `token-policy` (ADR 0003) confere `iss` e `aud` (`edge-gateway`, adicionada por um mapper em todos os clients), que o plugin `jwt` não confere.
- Em desenvolvimento, o realm usa um par RSA fixo gerado para este repositório (`keycloak/dev-keys/`, marcado DEV ONLY), para que a chave pública possa estar no `kong.yaml`.

## Consequências

- O gateway segue autenticando se o Keycloak cair: tokens já emitidos valem até expirar. Só novos logins falham (alerta `KeycloakDown`).
- Latência de autenticação é só verificação de assinatura, sem I/O.
- Revogação não é imediata: um token roubado vale até 5 minutos. Mitigação: vida curta e `revokeRefreshToken` no realm.
- **Rotação de chave exige atualizar o `kong.yaml`.** Isso é aceitável para a fundação e está nos próximos passos: um job que lê o JWKS e gera a configuração (publicando a chave nova antes de o Keycloak passar a assinar com ela).
- Os smoke tests conseguem forjar tokens com a chave dev para provar as rejeições de `iss`, `aud`, `exp` e `azp`.

## Alternativas consideradas

- **Introspecção (RFC 7662) a cada requisição**: revogação imediata, mas o Keycloak entra no caminho crítico de toda chamada e vira gargalo e ponto único de falha.
- **Plugin próprio que busca e cacheia o JWKS**: resolve a rotação, mas exige reimplementar verificação de assinatura e cache com invalidação; fica para depois, possivelmente como evolução do `token-policy`.
- **Um único consumer por issuer** (`key_claim_name: iss`): mais simples, mas perde a identidade do client e, com ela, o rate limit por cliente.
- **Kong Enterprise com plugin OIDC**: resolve tudo, com custo de licença.
