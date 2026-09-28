# infra-azure

Infraestrutura da Azure como código: **Terraform + GitHub Actions**, autenticação por **OIDC** (sem secrets), state remoto no **Azure Blob Storage**, um state e uma identidade por ambiente.

> **CI temporariamente desativado.** `plan.yml` e `apply.yml` estão com o gatilho automático comentado (só rodam via `workflow_dispatch`) porque o tenant do Entra ID bloqueia usuários comuns de registrar app registrations — as identidades OIDC do `bootstrap.sh` ainda não existem. Trabalhe com `terraform plan`/`apply` localmente (seção [Trabalhando localmente](#trabalhando-localmente)) até resolver isso com o TI e reativar os gatilhos.

---

## Estrutura

```
.
├── .github/workflows/
│   ├── plan.yml                  # PR: fmt, tflint, checkov, plan nos 3 ambientes
│   ├── apply.yml                 # main: dev -> stg -> prd, em cadeia
│   └── _terraform-apply.yml      # workflow reutilizável: plan -> aprovação -> apply
├── bootstrap/
│   └── bootstrap.sh              # roda UMA vez: cria state remoto + identidades OIDC
├── modules/                      # blocos reutilizáveis, sem valor hardcoded
│   ├── networking/               # VNet + subnets + um NSG por subnet
│   └── storage/                  # storage account com padrões seguros
├── envs/
│   ├── dev/                      # state próprio, resource group próprio, identidade própria
│   ├── stg/
│   └── prd/
├── .tflint.hcl
└── .pre-commit-config.yaml
```

Cada ambiente é um diretório raiz independente com o **seu próprio state**. Um erro em `dev` não tem como alcançar `prd`.

O isolamento entre ambientes não depende de subscriptions separadas. O `resource group` de cada ambiente é criado pelo `bootstrap.sh` — o Terraform só o **referencia** via `data source`, nunca cria nem destrói — e cada identidade de CI recebe `Contributor` apenas no RG do seu próprio ambiente. Mesmo com os três ambientes numa única subscription (caso comum em conta pessoal/Azure for Students), a identidade de `dev` não tem permissão para tocar em `prd`.

---

## Setup — do zero até o primeiro apply

### 1. Criar o repositório no GitHub

```bash
gh repo create minha-org/infra-azure --private --source=. --remote=origin
```

### 2. Rodar o bootstrap

O `bootstrap.sh` precisa de uma identidade com **Owner** na(s) subscription(s) e permissão para criar app registrations no Entra ID. Rode no Git Bash, WSL ou no Azure Cloud Shell.

```bash
az login
```

Depois exporte a configuração e execute. Se você tem uma subscription só (caso comum em conta pessoal/Azure for Students), não defina `SUBSCRIPTION_DEV`/`_STG`/`_PRD` — todos os ambientes caem na subscription atual:

```bash
GITHUB_ORG=minha-org GITHUB_REPO=infra-azure PREFIX=meuapp ./bootstrap/bootstrap.sh
```

`PREFIX` (e, se você mudar o padrão, `LOCATION_SHORT`) precisam ser **idênticos** ao `application`/`location_short` que você vai colocar em cada `envs/*/terraform.tfvars` — é essa combinação que forma o nome do resource group que o Terraform espera encontrar.

O que ele faz:

| Etapa | Resultado |
|---|---|
| Resource group + storage account do state | State remoto com versionamento, soft delete de 30 dias e lock `CanNotDelete` |
| Desabilita shared key no state | O state só é acessível por Entra ID / RBAC |
| 1 resource group por ambiente | `rg-meuapp-dev-brs`, `rg-meuapp-stg-brs`, `rg-meuapp-prd-brs` — o Terraform só os lê |
| 1 app registration por ambiente | `gh-meuapp-dev`, `gh-meuapp-stg`, `gh-meuapp-prd` |
| 3 federated credentials por app | `pull_request`, `ref:refs/heads/main`, `environment:<env>` |
| RBAC | `Contributor` **só no RG do próprio ambiente** + `Storage Blob Data Contributor` no state |
| Patch nos `backend.tf` | Preenche os placeholders `__STATE_*__` |

No fim ele imprime os comandos `gh variable set` já preenchidos.

### 3. Registrar as variáveis no GitHub

São **repository variables**, não secrets — nenhum desses valores é sigiloso (o segredo é a confiança federada, não o ID):

- `AZURE_TENANT_ID`
- `AZURE_CLIENT_ID_DEV` / `_STG` / `_PRD`
- `AZURE_SUBSCRIPTION_ID_DEV` / `_STG` / `_PRD`

### 4. Criar os GitHub Environments

Em **Settings → Environments**, crie `dev`, `stg` e `prd`. Em `stg` e `prd`, ligue **Required reviewers**. É esse gate — e só ele — que segura o `apply`.

### 5. Ajustar os `terraform.tfvars`

Troque `subscription_id`, `application`, `cost_center` e `owner` em cada `envs/*/terraform.tfvars`.

### 6. Commit e PR

```bash
git switch -c setup/infra-inicial
```

Abra o PR: o workflow de plan comenta o `terraform plan` dos três ambientes direto no PR.

---

## Como o CI funciona

**No PR** (`plan.yml`)

```
fmt -check → tflint → checkov → plan (dev, stg, prd em paralelo) → comentário no PR
```

O comentário é atualizado no lugar a cada push, em vez de acumular.

**No merge para `main`** (`apply.yml`)

```
dev: plan → [aprovação] → apply
      ↓
stg: plan → [aprovação] → apply
      ↓
prd: plan → [aprovação] → apply
```

Dois detalhes que importam:

- O `apply` recebe **o arquivo de plan** gerado no job anterior, baixado como artefato. O que foi revisado é exatamente o que vai para a Azure — não um plan recalculado que pode ter mudado no meio do caminho.
- Se o `plan` não encontrar mudanças (`-detailed-exitcode` = 0), o job de `apply` é pulado e ninguém é acordado para aprovar um no-op.

---

## Trabalhando localmente

Autentique-se e entre no diretório do ambiente:

```bash
az login
```

```bash
terraform -chdir=envs/dev init
```

```bash
terraform -chdir=envs/dev plan
```

Formatar tudo antes de commitar:

```bash
terraform fmt -recursive
```

Instalar os hooks de pre-commit (roda fmt, validate, tflint, checkov e terraform-docs a cada commit):

```bash
pre-commit install
```

---

## Convenções

**Nomenclatura** — `<tipo>-<app>-<env>-<região>`, ex.: `rg-meuapp-prd-brs`, `vnet-meuapp-prd-brs`, `snet-app-meuapp-prd-brs`. Storage accounts não aceitam hífen, então usam `st<app><env><sufixo>`.

**Tags** — `cost_center` e `owner` são obrigatórias (validadas em `variables.tf`, o plan falha sem elas). `environment`, `application`, `managed_by` e `repository` são adicionadas automaticamente.

**Rede** — um `/16` por ambiente: dev `10.10`, stg `10.20`, prd `10.30`. Cada subnet ganha um NSG dedicado.

**Versões** — `required_version` fixo e providers com `~>`. O `.terraform.lock.hcl` **deve** ser commitado; o CI roda `init -lockfile=readonly` e falha se ele estiver desatualizado. Para atualizar:

```bash
terraform -chdir=envs/dev init -upgrade
```

---

## Adicionando um recurso novo

1. Crie ou estenda um módulo em `modules/` — sem valores hardcoded, tudo por variável.
2. Chame o módulo em `envs/dev/main.tf` e parametrize em `envs/dev/terraform.tfvars`.
3. Abra o PR, leia o plan no comentário.
4. Depois de validado em dev, promova copiando a chamada para `stg` e `prd`.

A duplicação entre os `envs/` é intencional: ela permite que produção fique deliberadamente atrás de dev durante uma promoção.

---

## Pontos de atenção

- **A identidade de plan tem `Contributor`** — escopado ao resource group do próprio ambiente, não à subscription inteira, mas ainda é mais permissão do que um plan precisa. Endurecimento natural: um segundo app registration com apenas `Reader` + `Storage Blob Data Contributor` para os jobs de plan, deixando `Contributor` só no apply.
- **O artefato `tfplan` pode conter valores sensíveis.** A retenção está em 3 dias. Se houver segredos no state, restrinja quem baixa artefatos ou criptografe o plan antes do upload.
- **O resource group de cada ambiente não é gerenciado pelo Terraform.** Ele é criado pelo `bootstrap.sh` e referenciado via `data source` — não existe `terraform destroy` para ele. Para renomear ou mover o RG, é o `bootstrap.sh` (ou o `az cli` diretamente) que precisa mudar, não o `main.tf`.
- **`PREFIX`/`LOCATION_SHORT` do bootstrap e `application`/`location_short` do `terraform.tfvars` precisam bater exatamente.** Se divergirem, o `terraform plan` falha com "resource group não encontrado" — o data source procura um nome que o bootstrap nunca criou.
- **`shared_access_key_enabled = false`** na storage account da aplicação. Se alguma ferramenta legada precisar de connection string, ela vai quebrar; mude a variável explicitamente em vez de contornar por fora.
- **O `checkov` roda em modo bloqueante.** Para liberar um achado específico, use um comentário `#checkov:skip=CKV_AZURE_XX:motivo` no recurso — com o motivo escrito.
