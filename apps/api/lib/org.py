import re
from typing import Mapping

from .http import HttpError

DEV_ANONYMOUS = "dev-anonymous"
ENTRA = "entra"
ORG_RE = re.compile(r"org-[a-z0-9-]{1,40}")


def effective_mode(auth_mode: str) -> str:
    """Qualquer AUTH_MODE diferente de "dev-anonymous" vale como "entra": na dúvida, a API fecha."""
    return DEV_ANONYMOUS if auth_mode == DEV_ANONYMOUS else ENTRA


def resolve_org(params: Mapping[str, str], auth_mode: str, has_token: bool = False) -> str:
    """Decide de qual organização são os dados pedidos."""
    if effective_mode(auth_mode) == DEV_ANONYMOUS:
        # SÓ em dev, com dados fictícios: a organização vem do request.
        org = params.get("org") or ""
        # fullmatch, não match: com match, "org-a\n" passaria pelo $ do regex.
        if not ORG_RE.fullmatch(org):
            raise HttpError(400, "invalid organization", reason="invalid_org")
        return org

    # TODO(entra): validar o token do Entra ID (assinatura via JWKS, iss, aud,
    # exp) e tirar a organização da claim "roles". A organização NUNCA sai do
    # request no modo entra. Até lá, sem token = missing_token; com token =
    # auth_not_configured (o token não é lido nem registrado).
    reason = "auth_not_configured" if has_token else "missing_token"
    raise HttpError(401, "authentication not configured", reason=reason)
