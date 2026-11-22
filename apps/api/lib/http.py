import logging
from typing import Callable

HEADERS = {"Cache-Control": "no-store"}


class HttpError(Exception):
    """Erro com status HTTP. `reason` marca as negações de autorização."""

    def __init__(self, status: int, message: str, reason: str | None = None):
        super().__init__(message)
        self.status = status
        self.message = message
        self.reason = reason


def dispatch(handler: Callable[[], tuple[int, dict]]) -> tuple[int, dict]:
    """Executa o handler e converte qualquer falha em JSON {"error": ...}.

    Erros não previstos viram 500 genérico: o detalhe vai só para o log,
    nunca para o corpo da resposta.
    """
    try:
        return handler()
    except HttpError as e:
        return e.status, {"error": e.message}
    except Exception:
        logging.exception("erro não tratado na API")
        return 500, {"error": "internal error"}
