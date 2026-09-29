import json
import os

import azure.functions as func

from lib import posture as routes
from lib.cosmos import get_container
from lib.http import HEADERS, dispatch

# authLevel anônimo em todas as rotas: quem decide o acesso é o código,
# conforme AUTH_MODE (ver lib/org.py). Sem a variável, vale "entra" (401).
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def auth_mode() -> str:
    return os.environ.get("AUTH_MODE", "entra")


def respond(result: tuple[int, dict]) -> func.HttpResponse:
    status, body = result
    return func.HttpResponse(
        json.dumps(body, ensure_ascii=False),
        status_code=status,
        mimetype="application/json",
        headers=HEADERS,
    )


@app.route(route="health", methods=["GET"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    return respond(dispatch(routes.health))


@app.route(route="posture", methods=["GET"])
def posture(req: func.HttpRequest) -> func.HttpResponse:
    return respond(dispatch(lambda: routes.posture(req.params, get_container, auth_mode())))


@app.route(route="indicators/{key}/controls", methods=["GET"])
def controls(req: func.HttpRequest) -> func.HttpResponse:
    key = req.route_params.get("key", "")
    return respond(dispatch(lambda: routes.controls(req.params, key, get_container, auth_mode())))
