# ADR 0006: Vault com KV v2, PKI interna e AppRole, tudo por Terraform

- Status: Aceito
- Data: 2026-11-21

## Contexto

A borda lida com segredos (segredos de clients do Keycloak, credenciais de upstream) e vai precisar de mTLS entre gateway e upstreams. Os segredos não podem viver em arquivos do repositório nem ser copiados à mão do console do Keycloak.

## Decisão

Módulo `terraform/modules/vault-edge` (provider `hashicorp/vault`) que cria:

- **KV v2** em `edge/`, com `cas_required` (gravação exige check-and-set, evitando sobrescrita às cegas) e histórico de 10 versões;
- **PKI** em `edge-pki/`, CA interna com chave EC P-256 e papel `upstream-mtls` restrito ao domínio interno, para certificados de vida curta (24h padrão, 72h máximo);
- **AppRole** `edge-gateway` com token de 1h e `secret_id` de 24h;
- **Políticas** como templates HCL versionados: `edge-gateway` só lê `edge/data/gateway/*` e emite certificados; `edge-operator` administra segredos e certificados da borda, sem acesso a outros mounts;
- **audit device** em stdout.

No ambiente local, o Vault roda em modo dev (token `dev-only-root-token`) e o Terraform pode ser aplicado contra ele.

## Consequências

- Menor privilégio verificável em revisão de código: cada caminho permitido está num arquivo.
- A PKI já existe, mas o gateway ainda não usa mTLS com os upstreams (próximos passos).
- AppRole serve para workloads fora do Kubernetes; no cluster, o caminho certo é o auth method Kubernetes (próximos passos).
- Modo dev não tem persistência nem unseal: serve só para desenvolvimento.

## Alternativas consideradas

- **Kubernetes Secrets puros**: base64 não é criptografia; sem auditoria de leitura nem segredos dinâmicos.
- **Secrets manager do provedor de nuvem**: bom, mas amarra a plataforma a um provedor; o catálogo do projeto pede Vault.
- **SOPS no repositório**: bom para configuração estática; não emite certificados nem audita leitura.
