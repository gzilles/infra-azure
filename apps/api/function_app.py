import json
import os

import azure.functions as func

from lib import posture as routes
from lib.audit import client_ip
from lib.cosmos import get_container
from lib.http import HEADERS, dispatch

# authLevel anônimo em todas as rotas: quem decide o acesso é o código,
# conforme AUTH_MODE (ver lib/org.py). Sem a variável, vale "entra" (401).
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


def auth_mode() -> str:
    return os.environ.get("AUTH_MODE", "entra")


def request_context(req: func.HttpRequest) -> dict:
    """Só o que a autorização e a auditoria precisam: o IP já validado e se
    havia token. Os cabeçalhos em si não passam daqui."""
    return {
        "ip": client_ip(req.headers.get("x-forwarded-for")),
        "has_token": bool(req.headers.get("authorization")),
    }


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
    ctx = request_context(req)
    return respond(dispatch(lambda: routes.posture(req.params, get_container, auth_mode(), **ctx)))


@app.route(route="indicators/{key}/controls", methods=["GET"])
def controls(req: func.HttpRequest) -> func.HttpResponse:
    ctx = request_context(req)
    key = req.route_params.get("key", "")
    return respond(dispatch(lambda: routes.controls(req.params, key, get_container, auth_mode(), **ctx)))
