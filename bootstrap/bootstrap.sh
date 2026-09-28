#!/usr/bin/env bash
#
# Bootstrap do repositório de IaC.
#
# Cria, de forma idempotente:
#   1. Resource group + storage account + container para o state remoto do Terraform
#   2. Um resource group por ambiente (dev/stg/prd) — o Terraform passa a
#      REFERENCIAR esses RGs via data source, nunca a criá-los ou destruí-los
#   3. Um app registration por ambiente, com federated credentials para o GitHub Actions (OIDC)
#   4. RBAC de cada identidade, escopado ao resource group do próprio ambiente
#      (não à subscription inteira) — dev não enxerga prd mesmo numa subscription única
#   5. Preenche os placeholders em envs/*/backend.tf
#
# Rode UMA vez, com uma identidade que tenha Owner na(s) subscription(s)
# e permissão para criar app registrations no Entra ID.
#
# IMPORTANTE: PREFIX e LOCATION_SHORT aqui precisam ser IDÊNTICOS aos valores
# de `application` e `location_short` em cada envs/<env>/terraform.tfvars —
# é essa combinação que forma o nome do resource group
# (rg-<application>-<env>-<location_short>) que o Terraform vai procurar.
#
# Uso:
#   export GITHUB_ORG=minha-org
#   export GITHUB_REPO=infra-azure
#   export PREFIX=meuapp
#   export LOCATION_SHORT=brs
#   export SUBSCRIPTION_DEV=... SUBSCRIPTION_STG=... SUBSCRIPTION_PRD=...  # opcional, uma subscription só por padrão
#   ./bootstrap/bootstrap.sh
#
set -euo pipefail

# Git Bash (MSYS) converte argumentos iniciados por "/" em caminhos do Windows,
# corrompendo escopos como "/subscriptions/..." em `az role assignment`.
export MSYS_NO_PATHCONV=1

# ---------------------------------------------------------------- configuração

PREFIX="${PREFIX:-meuapp}"
LOCATION="${LOCATION:-brazilsouth}"
LOCATION_SHORT="${LOCATION_SHORT:-brs}"
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

# Cria a role assignment só se ela ainda não existir, e falha ALTO se a
# criação der erro — nunca trata "deu erro" como sinônimo de "já existia".
# É a lição do primeiro bootstrap real: um `|| echo "já existia"` cego
# mascarou uma falha de verdade e só apareceu como 403 no terraform init.
ensure_role_assignment() {
  local assignee_oid="$1" principal_type="$2" role="$3" scope="$4" label="$5"

  local existing
  existing="$(az role assignment list \
    --assignee-object-id "$assignee_oid" \
    --role "$role" \
    --scope "$scope" \
    --query "[0].id" -o tsv 2>/dev/null || echo "")"

  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    info "  ${label}: já existia"
    return 0
  fi

  if az role assignment create \
    --assignee-object-id "$assignee_oid" \
    --assignee-principal-type "$principal_type" \
    --role "$role" \
    --scope "$scope" \
    --output none; then
    info "  ${label}: concedida"
  else
    die "Falha ao conceder '${role}' (${label}) em ${scope}. Confira se você tem permissão para criar role assignments (Owner ou User Access Administrator)."
  fi
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

STATE_SUB="${STATE_SUBSCRIPTION:-$DEFAULT_SUB}"

log "Tenant: ${TENANT_ID}"
info "Subscription padrão: ${DEFAULT_SUB}"
info "Repositório GitHub: ${GITHUB_ORG}/${GITHUB_REPO}"
info "Ambientes: ${ENVIRONMENTS}"
info "Prefixo/região: ${PREFIX} / ${LOCATION_SHORT} (deve bater com terraform.tfvars)"

# ------------------------------------------------ 0. resource providers

REQUIRED_PROVIDERS="Microsoft.Web Microsoft.App Microsoft.DocumentDB Microsoft.Insights Microsoft.OperationalInsights"

# Registra em cada subscription realmente usada (state + cada ambiente),
# sem repetir a mesma subscription duas vezes — hoje é uma só, mas o script
# já suporta SUBSCRIPTION_DEV/STG/PRD apontando pra subscriptions diferentes.
subs_seen=""

register_providers_in() {
  local sub="$1" ns state
  case " $subs_seen " in
    *" $sub "*) return 0 ;;
  esac
  subs_seen="$subs_seen $sub"

  log "Resource providers em ${sub}"
  az account set --subscription "$sub"
  for ns in $REQUIRED_PROVIDERS; do
    state="$(az provider show --namespace "$ns" --query registrationState -o tsv 2>/dev/null || echo "")"
    if [ "$state" = "Registered" ]; then
      info "  ${ns}: já registrado"
      continue
    fi
    info "  ${ns}: registrando (pode levar alguns minutos)..."
    az provider register --namespace "$ns" --wait
    info "  ${ns}: registrado"
  done
}

register_providers_in "$STATE_SUB"
for env in $ENVIRONMENTS; do
  register_providers_in "$(subscription_for "$env")"
done

# -------------------------------------------------- 1. backend de state remoto

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
  # Evita "/dev/urandom | head -c N": head fecha o pipe cedo, tr recebe
  # SIGPIPE, e com pipefail isso aborta o script sem imprimir nenhum erro.
  suffix="$(printf '%05d' "$((RANDOM % 100000))")"
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
# --auth-mode login: sem isso, o CLI tenta buscar a chave de conta por
# padrão. Numa reexecução, a chave já foi desabilitada (passo abaixo) e a
# chamada é rejeitada com KeyBasedAuthenticationNotPermitted.
az storage container create \
  --name "$STATE_CONTAINER" \
  --account-name "$STATE_SA" \
  --auth-mode login \
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
  ensure_role_assignment "$CURRENT_USER_OID" "User" "Storage Blob Data Contributor" "$STATE_SA_ID" "você mesmo"
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
  env_rg="rg-${PREFIX}-${env}-${LOCATION_SHORT}"

  log "Ambiente '${env}' — identidade ${app_name} (subscription ${env_sub})"

  az account set --subscription "$env_sub"

  # O Terraform só REFERENCIA este RG (data source) — nunca cria nem destrói.
  # Isso também é uma trava de produção mais forte que prevent_destroy:
  # não existe verbo `terraform destroy` para algo que o Terraform não é dono.
  info "  Resource group: ${env_rg}"
  az group create \
    --name "$env_rg" \
    --location "$LOCATION" \
    --tags managed_by=bootstrap environment="$env" application="$PREFIX" \
    --output none
  env_rg_id="$(az group show --name "$env_rg" --query id -o tsv)"

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

  # RBAC: Contributor só no resource group do ambiente + acesso ao blob do state.
  # Escopado ao RG, não à subscription: a identidade de dev não enxerga prd
  # mesmo quando as duas vivem na mesma subscription.
  ensure_role_assignment "$sp_oid" "ServicePrincipal" "Contributor" "$env_rg_id" "Contributor em ${env_rg}"
  ensure_role_assignment "$sp_oid" "ServicePrincipal" "Storage Blob Data Contributor" "$STATE_SA_ID" "acesso ao state"

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

 Resource groups por ambiente (o Terraform só os referencia,
 nunca os cria nem destrói):
EOF

for env in $ENVIRONMENTS; do
  echo "   rg-${PREFIX}-${env}-${LOCATION_SHORT}"
done

cat <<EOF

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
