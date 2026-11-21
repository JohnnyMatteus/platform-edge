# ADR 0005: Realm exportado no ambiente local e Terraform nos ambientes reais

- Status: Aceito
- Data: 2026-11-21

## Contexto

O Keycloak precisa estar pronto em segundos no `docker compose up`, com usuários fictícios e uma chave de assinatura conhecida pelo gateway. Nos ambientes reais, o realm precisa ser gerenciado como código, com revisão e plano antes de aplicar, e sem usuários de teste.

## Decisão

- **Local**: `keycloak/realm-edge.json` importado com `start-dev --import-realm`. Contém papéis, clients, usuários fictícios e o par RSA dev.
- **Ambientes reais**: módulo Terraform `terraform/modules/keycloak-realm` (provider `keycloak/keycloak`), que cria realm, papéis, clients, mapper de audiência e papéis de service account. Usuários não são criados por Terraform: vêm de federação ou de cadastro.
- `terraform/envs/local` aplica o módulo contra a stack do compose num realm separado (`edge-iac`), o que prova que o módulo funciona sem interferir no realm dos smoke tests.
- Os segredos dos clients confidenciais gerados pelo Keycloak vão direto para o Vault (`vault_kv_secret_v2`).

## Consequências

- Duas descrições do mesmo modelo (JSON e Terraform) podem divergir. Mitigação: o checklist de PR pede as duas atualizações, e o próximo passo é gerar o JSON a partir de um `terraform apply` no ambiente local.
- O CI valida o Terraform (`fmt` e `validate`), mas não aplica; a aplicação contra a stack local foi verificada manualmente e está documentada no README.
- O estado do ambiente local fica em arquivo local; ambientes reais precisam de backend remoto com lock.

## Alternativas consideradas

- **Só Terraform também no local**: exigiria rodar `terraform apply` a cada `compose up` e esperar o Keycloak; a chave fixa do gateway também ficaria mais difícil.
- **keycloak-config-cli**: boa ferramenta de import idempotente, mas é mais um formato; Terraform já é o padrão de IaC do restante da plataforma.
- **Configurar pelo console**: sem revisão, sem histórico, sem reprodutibilidade.
