locals {
  category = "Security - ${var.application}"

  # Prefixo do evento de autorização da API (apps/api/lib/audit.py).
  authz = <<-KQL
    AppTraces
    | where Message startswith "AUTHZ "
    | extend e = parse_json(substring(Message, 6))
    | extend route = tostring(e.route), outcome = tostring(e.outcome), reason = tostring(e.reason),
             org = tostring(e.org), status = toint(e.status), ip = tostring(e.ip)
  KQL

  searches = {
    "authz-denials-by-reason" = {
      display_name = "AUTHZ: negações por motivo, rota e IP (1 h)"
      query        = <<-KQL
        ${local.authz}
        | where TimeGenerated > ago(1h) and outcome == "denied"
        | summarize denials = count(), first_seen = min(TimeGenerated), last_seen = max(TimeGenerated) by reason, route, ip
        | order by denials desc
      KQL
    }

    "authz-org-enumeration" = {
      display_name = "AUTHZ: IP testando mais de 3 organizações (1 h)"
      query        = <<-KQL
        ${local.authz}
        | where TimeGenerated > ago(1h)
        | summarize orgs = dcount(org), sample_orgs = make_set(org, 20), requests = count(),
                    denied = countif(outcome == "denied") by ip
        | where orgs > 3
        | order by orgs desc
      KQL
    }

    "authz-injection-attempts" = {
      display_name = "AUTHZ: entradas inválidas (org ou key) por IP (24 h)"
      query        = <<-KQL
        ${local.authz}
        | where TimeGenerated > ago(24h) and reason in ("invalid_org", "invalid_key")
        | summarize attempts = count(), reasons = make_set(reason), sample_orgs = make_set(org, 10),
                    first_seen = min(TimeGenerated), last_seen = max(TimeGenerated) by ip
        | order by attempts desc
      KQL
    }

    "cosmos-denied-requests" = {
      display_name = "Cosmos: requisições negadas (403) por IP e principal (24 h)"
      query        = <<-KQL
        CDBDataPlaneRequests
        | where TimeGenerated > ago(24h) and StatusCode == 403
        | summarize requests = count(), operations = make_set(OperationName), last_seen = max(TimeGenerated)
                    by ClientIpAddress, AadPrincipalId
        | order by requests desc
      KQL
    }

    "cosmos-unexpected-principal" = {
      display_name = "Cosmos: acesso a dados por principal diferente da Function (24 h)"
      query        = <<-KQL
        let expected = dynamic(${jsonencode(var.expected_cosmos_principal_ids)});
        CDBDataPlaneRequests
        | where TimeGenerated > ago(24h)
        | where isnotempty(AadPrincipalId) and AadPrincipalId !in (expected)
        | summarize requests = count(), statuses = make_set(StatusCode), operations = make_set(OperationName),
                    last_seen = max(TimeGenerated) by AadPrincipalId, ClientIpAddress
        | order by requests desc
      KQL
    }

    "web-writes-outside-deploy" = {
      display_name = "Site: escritas e exclusões no $web (7 dias, revisão manual)"
      query        = <<-KQL
        StorageBlobLogs
        | where TimeGenerated > ago(7d)
        | where AccountName == "${var.static_site_storage_account_name}" and Category in ("StorageWrite", "StorageDelete")
        | project TimeGenerated, OperationName, StatusCode, AuthenticationType, RequesterUpn, RequesterObjectId,
                  CallerIpAddress, Uri
        | order by TimeGenerated desc
      KQL
    }

    "storage-sharedkey-attempts" = {
      display_name = "Storage: uso ou tentativa de chave compartilhada (7 dias)"
      query        = <<-KQL
        StorageBlobLogs
        | where TimeGenerated > ago(7d)
        | where AuthenticationType =~ "AccountKey" or StatusText has "KeyBasedAuthenticationNotPermitted"
        // O serviço de change feed da própria Azure grava em $blobchangefeed e
        // $blobchangefeedsys pelo endpoint interno (*.store.core.windows.net), inalcançável
        // pela internet. Não filtrar por user agent: ele é controlado pelo cliente.
        | extend host = tostring(parse_url(Uri).Host), path = tostring(parse_url(Uri).Path)
        | where not(host endswith ".store.core.windows.net" and path matches regex @"^/[^/]+/[$]blobchangefeed(sys)?/")
        | summarize attempts = count(), operations = make_set(OperationName), statuses = make_set(StatusCode),
                    last_seen = max(TimeGenerated) by AccountName, StatusText, CallerIpAddress
        | order by attempts desc
      KQL
    }

    "control-plane-security-changes" = {
      display_name = "Plano de controle: RBAC, chaves, rede e diagnóstico (7 dias)"
      query        = <<-KQL
        AzureActivity
        | where TimeGenerated > ago(7d)
        | where OperationNameValue matches regex @"(?i)(roleassignments/(write|delete)|/listkeys/action|regeneratekey|networkrulesets|privateendpointconnections|diagnosticsettings/delete|basicpublishingcredentialspolicies/write|databaseaccounts/write|storageaccounts/write)"
        | project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller, CallerIpAddress, ResourceGroup,
                  Resource = tostring(split(_ResourceId, "/")[-1])
        | order by TimeGenerated desc
      KQL
    }

    "function-deployments" = {
      display_name = "Function: deploys e mudanças de configuração (30 dias)"
      query        = <<-KQL
        // O deploy do Flex (config-zip) não passa pelo ARM: o sinal é a escrita do pacote
        // no container de deploy. Mudanças de configuração e reinícios vêm do AzureActivity.
        let package_writes = StorageBlobLogs
            | where TimeGenerated > ago(30d)
            | where AccountName == "${var.host_storage_account_name}" and OperationName == "PutBlob"
            | where tostring(parse_url(Uri).Path) startswith "/${var.deployment_container_name}/"
            | project TimeGenerated, Source = "package", Operation = OperationName, Who = RequesterObjectId,
                      Detail = tostring(parse_url(Uri).Path);
        let arm_changes = AzureActivity
            | where TimeGenerated > ago(30d)
            | where _ResourceId has "/sites/${lower(var.function_app_name)}"
            | where OperationNameValue matches regex @"(?i)sites/(write|restart/action|syncfunctiontriggers/action|config/write|basicpublishingcredentialspolicies/write)"
            | project TimeGenerated, Source = "arm", Operation = OperationNameValue, Who = Caller,
                      Detail = ActivityStatusValue;
        union package_writes, arm_changes
        | order by TimeGenerated desc
      KQL
    }

    "api-health-and-latency" = {
      display_name = "API: taxa de erro e p95 por endpoint (24 h)"
      query        = <<-KQL
        AppRequests
        | where TimeGenerated > ago(24h)
        | summarize requests = count(), errors_5xx = countif(toint(ResultCode) >= 500),
                    client_errors_4xx = countif(toint(ResultCode) between (400 .. 499)),
                    p95_ms = round(percentile(DurationMs, 95), 1) by Name
        | extend error_rate_pct = round(100.0 * errors_5xx / requests, 2)
        | order by requests desc
      KQL
    }

    "log-ingestion-and-cap" = {
      display_name = "Log Analytics: ingestão por tabela e cota diária atingida (30 dias)"
      query        = <<-KQL
        let ingestion = Usage
            | where TimeGenerated > ago(30d)
            | summarize MB = round(sum(Quantity), 3) by Day = startofday(TimeGenerated), DataType
            | extend Event = "";
        let cap = _LogOperation
            | where TimeGenerated > ago(30d)
            | where Category =~ "Ingestion" or Detail has_any ("quota", "cap")
            | project Day = startofday(TimeGenerated), DataType = "_LogOperation", MB = real(null),
                      Event = strcat(Operation, ": ", Detail);
        union ingestion, cap
        | order by Day desc, MB desc
      KQL
    }
  }
}

resource "azurerm_log_analytics_saved_search" "this" {
  for_each = local.searches

  name                       = each.key
  log_analytics_workspace_id = var.log_analytics_workspace_id
  category                   = local.category
  display_name               = each.value.display_name
  query                      = each.value.query

  tags = var.tags
}
