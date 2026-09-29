import json
import logging
import os
import re

import azure.functions as func
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

# TODO(entra-id): authLevel FUNCTION é temporário, porque app registrations estão
# bloqueadas no tenant. Trocar por ANONYMOUS + validação de JWT (assinatura via
# JWKS, iss, aud, roles) e tirar a organização da claim do token, NUNCA da
# query string: hoje quem tem a function key lê qualquer organização.
app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

ORG_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
SYSTEM_FIELDS = ("_rid", "_self", "_etag", "_attachments", "_ts")

_container = None


def container():
    # Cliente reaproveitado entre execuções da mesma instância.
    global _container
    if _container is None:
        client = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential=DefaultAzureCredential())
        _container = client.get_database_client(os.environ["COSMOS_DATABASE"]).get_container_client(
            os.environ["COSMOS_CONTAINER"]
        )
    return _container


def json_response(body: dict, status: int = 200) -> func.HttpResponse:
    return func.HttpResponse(json.dumps(body, ensure_ascii=False), status_code=status, mimetype="application/json")


# Sem chave: health check não expõe dados e precisa funcionar para sondas.
@app.route(route="health", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def health(req: func.HttpRequest) -> func.HttpResponse:
    return json_response({"status": "ok"})


@app.route(route="posture", methods=["GET"])
def posture(req: func.HttpRequest) -> func.HttpResponse:
    org = req.params.get("org", "")
    if not ORG_ID.match(org):
        return json_response({"error": "parâmetro 'org' ausente ou inválido"}, 400)

    try:
        items = list(
            container().query_items(
                "SELECT * FROM c WHERE c.organizationId = @org",
                parameters=[{"name": "@org", "value": org}],
                partition_key=org,
            )
        )
    except Exception:
        logging.exception("falha ao ler o Cosmos DB para org=%s", org)
        return json_response({"error": "falha ao ler os dados"}, 502)

    documents = [{k: v for k, v in item.items() if k not in SYSTEM_FIELDS} for item in items]
    return json_response({"organizationId": org, "count": len(documents), "documents": documents})
