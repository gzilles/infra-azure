import logging
from typing import Callable

HEADERS = {"Cache-Control": "no-store"}


class HttpError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


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
