"""Testes da API com o Cosmos simulado em memória.

O fake é carregado com os mesmos documentos que scripts/seed/seed.py grava a
partir de apps/web/mock-data.js, então comparar a resposta com o mock testa o
caminho mock -> seed -> documentos -> API -> JSON do contrato.

    python apps/api/tests/test_api.py -v
"""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "apps" / "api"))
sys.path.insert(0, str(ROOT / "scripts" / "seed"))

from azure.cosmos.exceptions import CosmosResourceNotFoundError  # noqa: E402

import seed  # noqa: E402
from lib import posture as routes  # noqa: E402
from lib.http import dispatch  # noqa: E402
from lib.posture import CONTROLS_QUERY, POSTURE_QUERY  # noqa: E402

MOCK = seed.load_mock()
DEV = "dev-anonymous"


class FakeContainer:
    """Aceita só as duas queries que a API usa: qualquer outra falha o teste."""

    def __init__(self, docs_by_org: dict):
        self.docs = docs_by_org

    def _partition(self, org):
        return self.docs.get(org, [])

    def query_items(self, query, parameters=None, partition_key=None):
        assert partition_key is not None, "toda query precisa de partition_key"
        docs = self._partition(partition_key)
        if query == POSTURE_QUERY:
            return [d for d in docs if d["type"] in ("summary", "indicator")]
        if query == CONTROLS_QUERY:
            key = {p["name"]: p["value"] for p in parameters}["@key"]
            return [d for d in docs if d["type"] == "control" and d["indicatorKey"] == key]
        raise AssertionError(f"query inesperada: {query}")

    def read_item(self, item, partition_key):
        for d in self._partition(partition_key):
            if d["id"] == item:
                return d
        raise CosmosResourceNotFoundError(message="not found")


FAKE = FakeContainer(seed.all_documents(MOCK))


def get_fake():
    return FAKE


def call_posture(org=None, mode=DEV):
    params = {} if org is None else {"org": org}
    return dispatch(lambda: routes.posture(params, get_fake, mode))


def call_controls(key, org="org-a", mode=DEV):
    return dispatch(lambda: routes.controls({"org": org}, key, get_fake, mode))


class ContractTests(unittest.TestCase):
    def test_health(self):
        self.assertEqual(dispatch(routes.health), (200, {"status": "ok"}))

    def test_posture_equals_mock(self):
        for org in MOCK:
            with self.subTest(org=org):
                status, body = call_posture(org)
                self.assertEqual(status, 200)
                self.assertEqual(body, MOCK[org]["posture"])

    def test_controls_equal_mock(self):
        for org, data in MOCK.items():
            for ind in data["posture"]["indicators"]:
                with self.subTest(org=org, key=ind["key"]):
                    status, body = call_controls(ind["key"], org)
                    self.assertEqual(status, 200)
                    expected = {
                        "indicator": {"key": ind["key"], "name": ind["name"]},
                        "controls": data["controls"].get(ind["key"], []),
                    }
                    self.assertEqual(body, expected)

    def test_org_a_has_three_overdue_vuln_controls(self):
        _, body = call_controls("vuln-mgmt", "org-a")
        overdue = [c["id"] for c in body["controls"] if c["status"] == "overdue"]
        self.assertEqual(overdue, ["VM-01", "VM-02", "VM-03"])


class ValidationTests(unittest.TestCase):
    def test_invalid_org_is_400(self):
        for org in ["", "org-", "ORG-A", "org-a\n", "../../x", "org-a;drop", "x" * 50, None]:
            with self.subTest(org=org):
                self.assertEqual(call_posture(org), (400, {"error": "invalid organization"}))

    def test_unknown_org_is_404(self):
        self.assertEqual(call_posture("org-zzz"), (404, {"error": "organization not found"}))

    def test_invalid_key_is_400(self):
        for key in ["vuln-mgmt' OR 1=1 --", "VULN", "a/b", "vuln-mgmt\n", "", "x" * 41]:
            with self.subTest(key=key):
                self.assertEqual(call_controls(key), (400, {"error": "invalid indicator key"}))

    def test_unknown_indicator_is_404(self):
        self.assertEqual(call_controls("nao-existe"), (404, {"error": "indicator not found"}))


class AuthModeTests(unittest.TestCase):
    def test_entra_mode_is_401_before_anything_else(self):
        expected = (401, {"error": "authentication not configured"})
        for mode in ["entra", "", "ENTRA", "qualquer-coisa"]:
            with self.subTest(mode=mode):
                self.assertEqual(call_posture("org-a", mode=mode), expected)
                self.assertEqual(call_posture("../../x", mode=mode), expected)
                self.assertEqual(call_controls("vuln-mgmt' OR 1=1 --", mode=mode), expected)


class StatusTests(unittest.TestCase):
    def test_status_thresholds(self):
        cases = {100: "good", 80: "good", 79: "warning", 65: "warning", 64: "serious", 50: "serious", 49: "critical", 0: "critical"}
        for score, expected in cases.items():
            with self.subTest(score=score):
                self.assertEqual(routes.status_from_score(score), expected)


class ErrorHandlingTests(unittest.TestCase):
    def test_unexpected_error_is_generic_500(self):
        def broken():
            raise RuntimeError("detalhe interno que não pode vazar")

        with self.assertLogs(level="ERROR"):
            status, body = dispatch(lambda: routes.posture({"org": "org-a"}, broken, DEV))
        self.assertEqual((status, body), (500, {"error": "internal error"}))


if __name__ == "__main__":
    unittest.main()
