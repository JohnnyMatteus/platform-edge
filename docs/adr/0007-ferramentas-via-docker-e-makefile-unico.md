# ADR 0007: Ferramentas de validação via Docker, com um Makefile como contrato do CI

- Status: Aceito
- Data: 2026-11-21

## Contexto

O projeto usa Terraform, Helm, kubeconform, promtool, Kong e Go. Nem todos estão instalados nas máquinas de desenvolvimento, e versões diferentes entre a máquina e o CI geram o clássico "passa aqui, quebra lá".

## Decisão

- Toda ferramenta que não é Go roda por `docker run` com **imagem oficial de versão fixada** (`hashicorp/terraform:1.10.5`, `alpine/helm:3.17.0`, `ghcr.io/yannh/kubeconform:v0.6.7`, `prom/prometheus:v3.1.0`, `kong:3.9.1`).
- O `Makefile` é o contrato: o workflow do GitHub Actions só chama alvos do `make`. `make ci` roda localmente tudo o que o CI roda, menos os smoke tests (`make up && make smoke`).
- Os testes do plugin Lua usam o `luajit` da própria imagem do Kong, sem instalar `busted`.

## Consequências

- Única dependência local: Docker (e Go para o stub e os smoke tests).
- A primeira execução baixa imagens; depois fica em cache.
- Atualizar uma ferramenta é mudar uma linha do `Makefile` (Dependabot cobre actions, Dockerfiles e providers).
- O runner de testes Lua é mínimo (sem mocks nem relatórios); se a base de Lua crescer, vale migrar para `busted`.

## Alternativas consideradas

- **Actions específicas (setup-terraform, setup-helm)**: o CI ficaria diferente do local.
- **Imagem de toolbox única**: menos `docker run`, mas uma imagem a mais para construir e manter.
- **asdf/mise para fixar versões locais**: resolve a máquina, não garante paridade com o CI sem a mesma configuração lá.
