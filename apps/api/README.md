# Posture API

Azure Function (Python 3.13, Flex Consumption) que lê o Cosmos DB com a identidade gerenciada da Function e devolve os dados do dashboard. Não usa nenhuma chave.

| Rota | Resposta |
|---|---|
| `GET /api/health` | `{"status":"ok"}`, sem tocar no Cosmos |
| `GET /api/posture` | Score consolidado e indicadores da organização |
| `GET /api/indicators/{key}/controls` | Controles de um indicador |

O formato exato de cada resposta é o de `apps/web/mock-data.js`, que também alimenta o seed do Cosmos. Os testes comparam as duas coisas.

## Autenticação: `AUTH_MODE`

| Valor | Comportamento |
|---|---|
| `entra` (padrão) | Responde `401 {"error":"authentication not configured"}` em `/posture` e `/controls` até o login com Entra ID ser implementado. Qualquer valor desconhecido também cai aqui. |
| `dev-anonymous` | Sem login. A organização vem do parâmetro `?org=`, validado contra `^org-[a-z0-9-]{1,40}$`. |

**`dev-anonymous` é inseguro por definição.** Qualquer pessoa pode ler qualquer organização trocando o `?org=` na URL, o que contraria a regra "a organização vem do token, nunca do request". Ele só é aceitável em dev, com dados fictícios, e só é ligado em `envs/dev/terraform.tfvars` (`api_auth_mode`). stg e prd ficam no padrão `entra`.

O ponto a trocar quando o Entra ID existir é `resolve_org` em `lib/org.py`, marcado com `TODO(entra)`.

## Evento de autorização: `AUTHZ`

Cada decisão de autorização em `/posture` e `/controls` gera uma linha de log, que vai para a tabela `traces` do Application Insights:

```
AUTHZ {"route":"/posture","authMode":"dev-anonymous","outcome":"denied","reason":"invalid_org","org":"??????x","status":400,"ip":"203.0.113.7"}
```

| Campo | Conteúdo |
|---|---|
| `route` | O modelo da rota (`/indicators/{key}/controls`), nunca a URL real |
| `outcome` | `allowed` ou `denied` |
| `reason` | `ok`, `missing_token`, `auth_not_configured`, `invalid_org`, `unknown_org`, `invalid_key`, `unknown_indicator` |
| `org` | O valor pedido, truncado em 40 caracteres, só com `[a-z0-9-]` (o resto vira `?`) |
| `ip` | O IP do cliente, tirado do `X-Forwarded-For` e validado. Se não for um IP, vira `unknown`. |

Token, cabeçalhos, cookies, query string e corpo nunca são registrados. A Function só repassa à lógica de autorização o IP já validado e se havia token, sem o valor dele. O teste `NoSecretsTests` chama a Function com token, cookie e query string marcados e confere que nenhum deles aparece em log algum.

Falhas inesperadas (500) não são decisão de autorização e não geram evento.

## Estrutura

- `function_app.py`: registra as rotas e converte o resultado em HTTP. Não contém regra de negócio.
- `lib/posture.py`: monta as respostas no formato do contrato.
- `lib/org.py`: resolve a organização conforme `AUTH_MODE`.
- `lib/audit.py`: monta o evento `AUTHZ`, sanitiza o `org` e valida o IP.
- `lib/cosmos.py`: cliente do Cosmos, reaproveitado entre invocações.
- `lib/http.py`: erros sempre em JSON e `500` genérico, com o detalhe só no log.

Toda consulta ao Cosmos usa a organização como partition key e parâmetros, nunca texto concatenado.

## Testes

Rodam sem Azure, com o Cosmos simulado em memória:

```bash
python apps/api/tests/test_api.py -v
```

```bash
python apps/api/tests/test_audit.py -v
```

Precisam de `azure-cosmos` e `azure-functions` instalados.
