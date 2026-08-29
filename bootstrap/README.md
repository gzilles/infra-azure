# bootstrap

O problema do ovo e da galinha: o state remoto do Terraform precisa existir **antes** do Terraform rodar. Este diretório resolve isso com um script imperativo, executado uma única vez.

## Pré-requisitos

- `az` (Azure CLI) e `jq`
- `az login` com uma identidade que tenha:
  - **Owner** na(s) subscription(s) — para criar role assignments
  - Permissão para criar app registrations no Entra ID (papel *Application Developer* ou superior)
- Bash: Git Bash, WSL ou Azure Cloud Shell

## Variáveis

| Variável | Obrigatória | Padrão | O que é |
|---|---|---|---|
| `GITHUB_ORG` | sim | — | Organização ou usuário dono do repositório |
| `GITHUB_REPO` | sim | — | Nome do repositório |
| `PREFIX` | não | `meuapp` | Prefixo de nomenclatura |
| `LOCATION` | não | `brazilsouth` | Região da Azure |
| `ENVIRONMENTS` | não | `dev stg prd` | Lista separada por espaço |
| `STATE_RG` | não | `rg-tfstate-<PREFIX>` | Resource group do state |
| `STATE_SUBSCRIPTION` | não | subscription atual | Onde o state vive |
| `SUBSCRIPTION_DEV` | não | subscription atual | Subscription do ambiente dev |
| `SUBSCRIPTION_STG` | não | subscription atual | Subscription do ambiente stg |
| `SUBSCRIPTION_PRD` | não | subscription atual | Subscription do ambiente prd |
| `STATE_RETENTION_DAYS` | não | `30` | Soft delete do state |

## Execução

```bash
GITHUB_ORG=minha-org GITHUB_REPO=infra-azure PREFIX=meuapp ./bootstrap/bootstrap.sh
```

O script é **idempotente**: rodar de novo reaproveita a storage account existente (identificada pela tag `purpose=terraform-state`), os app registrations pelo display name e as federated credentials pelo subject.

## O que é criado

**State remoto** — resource group com lock `CanNotDelete`, storage account ZRS com versionamento, soft delete de blob e de container, TLS 1.2 mínimo, acesso público de blob desabilitado e autenticação por chave compartilhada desligada.

**Uma identidade por ambiente** — `gh-<PREFIX>-<env>`, cada uma com três federated credentials:

| Subject | Usado por |
|---|---|
| `repo:ORG/REPO:pull_request` | job de plan no PR |
| `repo:ORG/REPO:ref:refs/heads/main` | job de plan após o merge |
| `repo:ORG/REPO:environment:<env>` | job de apply, atrás do gate |

Nenhum client secret é criado em nenhum momento. O GitHub troca um token OIDC de curta duração pelo token da Azure a cada execução.

## Se precisar refazer

Para recomeçar do zero (**apaga o state — os recursos gerenciados ficam órfãos**):

```bash
az lock delete --name protect-tfstate --resource-group rg-tfstate-meuapp
```

Depois remova o resource group e os app registrations `gh-meuapp-*` manualmente. Faça isso só se souber exatamente o que está descartando.
