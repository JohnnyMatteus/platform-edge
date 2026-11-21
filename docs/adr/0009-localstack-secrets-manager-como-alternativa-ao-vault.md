# ADR 0009: LocalStack Secrets Manager como alternativa comparada ao Vault

- Status: Aceito
- Data: 2026-11-21

## Contexto

O ADR 0006 escolheu o Vault como cofre de segredos da borda. Times que já operam na AWS costumam preferir o AWS Secrets Manager, e o ecossistema do portfólio tem projetos que usam LocalStack para emular a AWS. Vale registrar a comparação e deixar as duas opções executáveis localmente, sem trocar o cofre principal.

## Decisão

- O **Vault continua o cofre principal**: é o que o Terraform configura (`terraform/modules/vault-edge`) e o único que a arquitetura da borda pressupõe.
- O profile `tools` do compose sobe o **LocalStack só com `secretsmanager`**. O script `init/aws/01-edge-secrets.sh` cria os mesmos segredos de client que o Terraform grava no Vault (`edge/keycloak/clients/<client>`), com valores DEV ONLY.
- Nenhum componente do gateway lê do LocalStack. Ele existe para comparar a experiência e para quem for portar a borda para AWS.

| Critério | Vault | AWS Secrets Manager (LocalStack em dev) |
| --- | --- | --- |
| Segredos estáticos (KV) | KV v2 com versões e check-and-set | Versões com rótulos (`AWSCURRENT`, `AWSPREVIOUS`) |
| Certificados para mTLS | PKI nativa, certificados de vida curta | Exige ACM Private CA (serviço separado, pago) |
| Segredos dinâmicos (banco, nuvem) | Engines dedicados, credencial por lease | Rotação via Lambda escrita por nós |
| Autenticação de workload | AppRole, Kubernetes, OIDC, AWS IAM | IAM (IRSA no EKS) |
| Política de acesso | HCL por caminho, versionada | IAM policy por ARN |
| Auditoria | Audit device com cada leitura | CloudTrail |
| Operação | Cluster, unseal, backup e upgrade por nossa conta (ou HCP) | Gerenciado |
| Portabilidade | Qualquer nuvem ou on-premises | Só AWS |
| Emulação local | Modo dev oficial | LocalStack (fidelidade boa para Secrets Manager) |

## Consequências

- Quem conhece a AWS consegue comparar os dois fluxos lado a lado: `make up PROFILES=core,tools` e `awslocal secretsmanager get-secret-value --secret-id edge/keycloak/clients/partner-batch`.
- Os segredos de exemplo ficam duplicados em dois lugares no ambiente local. São valores dev e o script é idempotente.
- Se a plataforma for para AWS sem necessidade de PKI e segredos dinâmicos, a troca é viável: o gateway recebe segredos por variável de ambiente e não conhece o cofre.

## Alternativas consideradas

- **Trocar o Vault pelo Secrets Manager**: perderia a PKI para mTLS e os segredos dinâmicos, que são o motivo da escolha do Vault.
- **Não emular a AWS**: mais simples, mas deixaria a comparação só no papel.
- **Usar o LocalStack também para KMS e ACM**: ACM Private CA no LocalStack não emitiria certificados úteis para o mTLS local; não agrega.
