#!/usr/bin/env bash
#
# Bootstrap do repositório de IaC.
#
# Cria, de forma idempotente:
#   1. Resource group + storage account + container para o state remoto do Terraform
#   2. Um app registration por ambiente, com federated credentials para o GitHub Actions (OIDC)
#   3. As permissões RBAC de cada identidade
#   4. Preenche os placeholders em envs/*/backend.tf
#
# Rode UMA vez, com uma identidade que tenha Owner na(s) subscription(s)
# e permissão para criar app registrations no Entra ID.
#
# Uso:
#   export GITHUB_ORG=minha-org
#   export GITHUB_REPO=infra-azure
#   export PREFIX=meuapp
#   export SUBSCRIPTION_DEV=... SUBSCRIPTION_STG=... SUBSCRIPTION_PRD=...
#   ./bootstrap/bootstrap.sh
#
set -euo pipefail

# ---------------------------------------------------------------- configuração

PREFIX="${PREFIX:-meuapp}"
LOCATION="${LOCATION:-brazilsouth}"
ENVIRONMENTS="${ENVIRONMENTS:-dev stg prd}"
STATE_RG="${STATE_RG:-rg-tfstate-${PREFIX}}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
STATE_RETENTION_DAYS="${STATE_RETENTION_DAYS:-30}"

GITHUB_ORG="${GITHUB_ORG:?Defina GITHUB_ORG (a organização ou usuário dono do repositório)}"
GITHUB_REPO="${GITHUB_REPO:?Defina GITHUB_REPO (o nome do repositório)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ------------------------------------------------------------------- utilidades

log()  { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m [!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m [x] %s\033[0m\n' "$*" >&2; exit 1; }

retry() {
  local attempts=$1 delay=$2; shift 2
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then return 1; fi
    sleep "$delay"
    n=$((n + 1))
  done
}

command -v az >/dev/null || die "Azure CLI (az) não encontrada."
command -v jq >/dev/null || die "jq não encontrado."
az account show >/dev/null 2>&1 || die "Você não está logado. Rode 'az login' primeiro."

DEFAULT_SUB="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
CURRENT_USER_OID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")"

# Resolve a subscription do ambiente: SUBSCRIPTION_DEV, SUBSCRIPTION_STG, ...
subscription_for() {
  local env_upper var value
  env_upper="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
  var="SUBSCRIPTION_${env_upper}"
  value="${!var:-}"
  echo "${value:-$DEFAULT_SUB}"
}

log "Tenant: ${TENANT_ID}"
info "Subscription padrão: ${DEFAULT_SUB}"
info "Repositório GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
info "Ambientes: ${ENVIRONMENTS}"

# -------------------------------------------------- 1. backend de state remoto

STATE_SUB="${STATE_SUBSCRIPTION:-$DEFAULT_SUB}"
az account set --subscription "$STATE_SUB"

log "Resource group do state: ${STATE_RG}"
az group create \
  --name "$STATE_RG" \
  --location "$LOCATION" \
  --tags purpose=terraform-state managed_by=bootstrap \
  --output none

# Reaproveita a conta existente, se o bootstrap já rodou antes.
STATE_SA="$(az storage account list \
  --resource-group "$STATE_RG" \
  --query "[?tags.purpose=='terraform-state'] | [0].name" -o tsv 2>/dev/null || echo "")"

if [ -z "$STATE_SA" ] || [ "$STATE_SA" = "null" ]; then
  suffix="$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)"
  short_prefix="$(echo "$PREFIX" | tr -cd 'a-z0-9' | cut -c1-10)"
  STATE_SA="st${short_prefix}tfstate${suffix}"

  log "Criando storage account do state: ${STATE_SA}"
  az storage account create \
    --name "$STATE_SA" \
    --resource-group "$STATE_RG" \
    --location "$LOCATION" \
    --sku Standard_ZRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --tags purpose=terraform-state managed_by=bootstrap \
    --output none
else
  log "Storage account do state já existe: ${STATE_SA}"
fi

log "Habilitando versionamento e soft delete no state"
# Versionamento é a rede de segurança quando alguém corrompe o state.
az storage account blob-service-properties update \
  --account-name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days "$STATE_RETENTION_DAYS" \
  --enable-container-delete-retention true \
  --container-delete-retention-days "$STATE_RETENTION_DAYS" \
  --output none

log "Criando container ${STATE_CONTAINER}"
az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --public-access off \
  --output none

STATE_SA_ID="$(az storage account show --name "$STATE_SA" --resource-group "$STATE_RG" --query id -o tsv)"

# Só a partir daqui a conta passa a exigir Entra ID; o container já existe.
log "Desabilitando autenticação por chave compartilhada no state"
az storage account update \
  --name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --allow-shared-key-access false \
  --output none

if [ -n "$CURRENT_USER_OID" ]; then
  info "Concedendo 'Storage Blob Data Contributor' a você mesmo (para rodar plan local)"
  az role assignment create \
    --assignee-object-id "$CURRENT_USER_OID" \
    --assignee-principal-type User \
    --role "Storage Blob Data Contributor" \
    --scope "$STATE_SA_ID" \
    --output none 2>/dev/null || info "  (já existia)"
fi

info "Aplicando lock CanNotDelete no resource group do state"
az lock create \
  --name "protect-tfstate" \
  --lock-type CanNotDelete \
  --resource-group "$STATE_RG" \
  --output none 2>/dev/null || warn "Não foi possível criar o lock (precisa de Owner/User Access Administrator)."

# ------------------------------------- 2. identidades OIDC, uma por ambiente

declare -a SUMMARY_LINES=()

for env in $ENVIRONMENTS; do
  env_sub="$(subscription_for "$env")"
  app_name="gh-${PREFIX}-${env}"

  log "Ambiente '${env}' — identidade ${app_name} (subscription ${env_sub})"

  app_id="$(az ad app list --display-name "$app_name" --query "[0].appId" -o tsv 2>/dev/null || echo "")"
  if [ -z "$app_id" ] || [ "$app_id" = "null" ]; then
    app_id="$(az ad app create --display-name "$app_name" --query appId -o tsv)"
    info "App registration criado: ${app_id}"
  else
    info "App registration já existe: ${app_id}"
  fi

  # O Entra ID leva alguns segundos para propagar o app recém-criado.
  if ! az ad sp show --id "$app_id" >/dev/null 2>&1; then
    retry 12 5 az ad sp create --id "$app_id" --output none \
      || die "Não consegui criar o service principal de ${app_name}."
    info "Service principal criado"
  fi
  sp_oid="$(az ad sp show --id "$app_id" --query id -o tsv)"

  # Três credenciais federadas, uma por contexto em que o workflow roda:
  #   pull_request        -> job de plan no PR
  #   ref:refs/heads/main -> job de plan após o merge
  #   environment:<env>   -> job de apply, atrás do gate de aprovação
  existing_subjects="$(az ad app federated-credential list --id "$app_id" --query "[].subject" -o tsv 2>/dev/null || echo "")"

  add_federated_credential() {
    local name="$1" subject="$2"
    if echo "$existing_subjects" | grep -qx "$subject"; then
      info "  credencial federada já existe: ${subject}"
      return 0
    fi
    az ad app federated-credential create --id "$app_id" --parameters "$(jq -n \
      --arg name "$name" \
      --arg subject "$subject" \
      '{
         name: $name,
         issuer: "https://token.actions.githubusercontent.com",
         subject: $subject,
         audiences: ["api://AzureADTokenExchange"]
       }')" --output none
    info "  credencial federada criada: ${subject}"
  }

  repo_ref="repo:${GITHUB_ORG}/${GITHUB_REPO}"
  add_federated_credential "${env}-pull-request" "${repo_ref}:pull_request"
  add_federated_credential "${env}-main-branch"  "${repo_ref}:ref:refs/heads/main"
  add_federated_credential "${env}-environment"  "${repo_ref}:environment:${env}"

  # RBAC: Contributor na subscription do ambiente + acesso ao blob do state.
  info "  Contributor em /subscriptions/${env_sub}"
  az role assignment create \
    --assignee-object-id "$sp_oid" \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/${env_sub}" \
    --output none 2>/dev/null || info "  (já existia)"

  info "  Storage Blob Data Contributor no state"
  az role assignment create \
    --assignee-object-id "$sp_oid" \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" \
    --scope "$STATE_SA_ID" \
    --output none 2>/dev/null || info "  (já existia)"

  env_upper="$(echo "$env" | tr '[:lower:]' '[:upper:]')"
  SUMMARY_LINES+=("gh variable set AZURE_CLIENT_ID_${env_upper} --body \"${app_id}\"")
  SUMMARY_LINES+=("gh variable set AZURE_SUBSCRIPTION_ID_${env_upper} --body \"${env_sub}\"")
done

# ------------------------------------------- 3. preencher os backend.tf locais

log "Preenchendo envs/*/backend.tf"
for env in $ENVIRONMENTS; do
  f="${REPO_ROOT}/envs/${env}/backend.tf"
  if [ ! -f "$f" ]; then
    warn "envs/${env}/backend.tf não encontrado, pulando."
    continue
  fi
  tmp="$(mktemp)"
  sed -e "s/__STATE_RESOURCE_GROUP__/${STATE_RG}/g" \
      -e "s/__STATE_STORAGE_ACCOUNT__/${STATE_SA}/g" "$f" > "$tmp"
  mv "$tmp" "$f"
  info "envs/${env}/backend.tf atualizado"
done

# ------------------------------------------------------------------ resultado

cat <<EOF

============================================================
 Bootstrap concluído
============================================================

 State remoto
   resource group  : ${STATE_RG}
   storage account : ${STATE_SA}
   container       : ${STATE_CONTAINER}

 Agora registre as variáveis no GitHub (repository variables,
 NÃO secrets — nenhum desses valores é secreto):

   gh variable set AZURE_TENANT_ID --body "${TENANT_ID}"
EOF

for line in "${SUMMARY_LINES[@]}"; do
  echo "   $line"
done

cat <<'EOF'

 Depois, em Settings > Environments, crie os environments
 "dev", "stg" e "prd" e configure "Required reviewers" em
 stg e prd — é esse gate que segura o apply.

 Por fim, faça commit dos backend.tf atualizados.

============================================================
EOF
