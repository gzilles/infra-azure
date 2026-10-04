"""Evento estruturado de decisão de autorização, uma linha por decisão.

    AUTHZ {"route":"/posture","authMode":"dev-anonymous","outcome":"denied",...}

Nada que venha do cliente entra no log sem tratamento: o org é truncado e
reduzido a [a-z0-9-] e o IP só entra se for um endereço válido. Token,
cabeçalhos, query string e corpo nunca são registrados.
"""

import ipaddress
import json
import logging
import re

PREFIX = "AUTHZ "
ORG_MAX = 40
_NOT_ORG_CHAR = re.compile(r"[^a-z0-9-]")

logger = logging.getLogger("authz")


def sanitize_org(value: str | None) -> str:
    return _NOT_ORG_CHAR.sub("?", (value or "")[:ORG_MAX])


def client_ip(forwarded_for: str | None) -> str:
    """Primeiro endereço do X-Forwarded-For, sem porta, se for um IP válido.

    A plataforma da Azure acrescenta o IP de origem como "ip:porta" (IPv4) ou
    "[ip]:porta" (IPv6). Qualquer coisa que não seja um IP vira "unknown".
    """
    first = (forwarded_for or "").split(",")[0].strip()
    if first.startswith("["):
        first = first[1 : first.find("]")] if "]" in first else ""
    elif first.count(":") == 1:
        first = first.split(":")[0]
    try:
        return str(ipaddress.ip_address(first))
    except ValueError:
        return "unknown"


def authz(route: str, auth_mode: str, outcome: str, reason: str, org: str | None, status: int, ip: str) -> str:
    event = {
        "route": route,
        "authMode": auth_mode,
        "outcome": outcome,
        "reason": reason,
        "org": sanitize_org(org),
        "status": status,
        "ip": ip,
    }
    line = PREFIX + json.dumps(event, separators=(",", ":"))
    logger.info(line)
    return line
