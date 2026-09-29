import re
from typing import Mapping

from .http import HttpError

DEV_ANONYMOUS = "dev-anonymous"
ORG_RE = re.compile(r"org-[a-z0-9-]{1,40}")


def resolve_org(params: Mapping[str, str], auth_mode: str) -> str:
    """Decide de qual organização são os dados pedidos.

    Qualquer AUTH_MODE diferente de "dev-anonymous" cai no modo "entra":
    na dúvida, a API fecha.
    """
    if auth_mode == DEV_ANONYMOUS:
        # SÓ em dev, com dados fictícios: a organização vem do request.
        org = params.get("org") or ""
        # fullmatch, não match: com match, "org-a\n" passaria pelo $ do regex.
        if not ORG_RE.fullmatch(org):
            raise HttpError(400, "invalid organization")
        return org

    # TODO(entra): validar o token do Entra ID (assinatura via JWKS, iss, aud,
    # exp) e tirar a organização da claim "roles". A organização NUNCA sai do
    # request no modo entra.
    raise HttpError(401, "authentication not configured")
