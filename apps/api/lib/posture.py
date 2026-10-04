import re
from typing import Callable, Mapping

from azure.cosmos.exceptions import CosmosResourceNotFoundError

from . import audit
from .http import HttpError
from .org import effective_mode, resolve_org

KEY_RE = re.compile(r"[a-z0-9-]{1,40}")

POSTURE_QUERY = "SELECT * FROM c WHERE c.type IN ('summary','indicator')"
CONTROLS_QUERY = "SELECT * FROM c WHERE c.type = 'control' AND c.indicatorKey = @key"

# Rotas registradas pelo modelo, não pela URL real: o key do request nunca vai para o log.
POSTURE_ROUTE = "/posture"
CONTROLS_ROUTE = "/indicators/{key}/controls"


def status_from_score(score: int) -> str:
    if score >= 80:
        return "good"
    if score >= 65:
        return "warning"
    if score >= 50:
        return "serious"
    return "critical"


def health() -> tuple[int, dict]:
    return 200, {"status": "ok"}


def _audited(route: str, params: Mapping[str, str], auth_mode: str, ip: str, handler: Callable) -> tuple[int, dict]:
    """Registra um evento AUTHZ por decisão: liberada (ok) ou negada (com o motivo).

    Erros sem motivo (falha inesperada, 500) não são decisão de autorização e
    seguem para o tratamento genérico sem evento.
    """
    mode = effective_mode(auth_mode)
    org = params.get("org")
    try:
        status, body = handler()
    except HttpError as e:
        if e.reason:
            audit.authz(route, mode, "denied", e.reason, org, e.status, ip)
        raise
    audit.authz(route, mode, "allowed", "ok", org, status, ip)
    return status, body


# Os campos da resposta são montados um a um: nada do documento do Cosmos é
# repassado por inteiro, então campos internos (_rid, _etag...) nunca vazam.


def posture(
    params: Mapping[str, str],
    get_container: Callable,
    auth_mode: str,
    ip: str = "unknown",
    has_token: bool = False,
) -> tuple[int, dict]:
    def handler():
        org = resolve_org(params, auth_mode, has_token)
        docs = list(get_container().query_items(POSTURE_QUERY, partition_key=org))

        summary = next((d for d in docs if d.get("type") == "summary"), None)
        if summary is None:
            raise HttpError(404, "organization not found", reason="unknown_org")

        indicators = sorted(
            (d for d in docs if d.get("type") == "indicator"),
            key=lambda d: (d.get("order", 999), d.get("key", "")),
        )
        return 200, {
            "organization": {"id": org, "name": summary["organizationName"]},
            "updatedAt": summary["updatedAt"],
            "score": summary["score"],
            "previousScore": summary["previousScore"],
            "indicators": [
                {
                    "key": d["key"],
                    "name": d["name"],
                    "score": d["score"],
                    "previousScore": d["previousScore"],
                    "status": d.get("status") or status_from_score(d["score"]),
                    "trend": d.get("trend", []),
                }
                for d in indicators
            ],
        }

    return _audited(POSTURE_ROUTE, params, auth_mode, ip, handler)


def controls(
    params: Mapping[str, str],
    key: str,
    get_container: Callable,
    auth_mode: str,
    ip: str = "unknown",
    has_token: bool = False,
) -> tuple[int, dict]:
    def handler():
        org = resolve_org(params, auth_mode, has_token)
        if not KEY_RE.fullmatch(key or ""):
            raise HttpError(400, "invalid indicator key", reason="invalid_key")

        container = get_container()
        try:
            indicator = container.read_item(f"indicator:{key}", partition_key=org)
        except CosmosResourceNotFoundError:
            raise HttpError(404, "indicator not found", reason="unknown_indicator") from None

        items = container.query_items(
            CONTROLS_QUERY,
            parameters=[{"name": "@key", "value": key}],
            partition_key=org,
        )
        rows = sorted(items, key=lambda d: d.get("controlId", ""))
        return 200, {
            "indicator": {"key": indicator["key"], "name": indicator["name"]},
            "controls": [
                {
                    "id": d["controlId"],
                    "name": d["name"],
                    "owner": d["owner"],
                    "dueDate": d["dueDate"],
                    "status": d["status"],
                }
                for d in rows
            ],
        }

    return _audited(CONTROLS_ROUTE, params, auth_mode, ip, handler)
