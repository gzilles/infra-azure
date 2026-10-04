"""Testes do evento AUTHZ: cada motivo, sanitização, IP e ausência de segredos.

    python apps/api/tests/test_audit.py -v
"""

import json
import logging
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_api  # noqa: E402  (ajusta o sys.path e fornece o Cosmos simulado)

from lib import audit  # noqa: E402
from lib import posture as routes  # noqa: E402
from lib.http import dispatch  # noqa: E402

DEV = "dev-anonymous"


def events(fn) -> tuple[tuple[int, dict], list[dict]]:
    """Roda a chamada e devolve o resultado e os eventos AUTHZ emitidos."""
    tc = unittest.TestCase()
    with tc.assertLogs("authz", level="INFO") as cm:
        result = fn()
    lines = [r.getMessage() for r in cm.records]
    for line in lines:
        assert line.startswith(audit.PREFIX), line
    return result, [json.loads(line[len(audit.PREFIX):]) for line in lines]


def posture(org="org-a", mode=DEV, has_token=False, ip="203.0.113.7"):
    params = {} if org is None else {"org": org}
    return events(lambda: dispatch(lambda: routes.posture(params, test_api.get_fake, mode, ip=ip, has_token=has_token)))


def controls(key, org="org-a", mode=DEV):
    return events(lambda: dispatch(lambda: routes.controls({"org": org}, key, test_api.get_fake, mode, ip="203.0.113.7")))


class ReasonTests(unittest.TestCase):
    def check(self, call, outcome, reason, status, route):
        (got_status, _), evs = call
        self.assertEqual(got_status, status)
        self.assertEqual(len(evs), 1, "um evento por decisão")
        e = evs[0]
        self.assertEqual((e["outcome"], e["reason"], e["status"], e["route"]), (outcome, reason, status, route))
        self.assertEqual(e["ip"], "203.0.113.7")

    def test_ok_posture(self):
        self.check(posture("org-a"), "allowed", "ok", 200, "/posture")

    def test_ok_controls(self):
        self.check(controls("vuln-mgmt"), "allowed", "ok", 200, "/indicators/{key}/controls")

    def test_missing_token(self):
        self.check(posture(mode="entra", has_token=False), "denied", "missing_token", 401, "/posture")

    def test_auth_not_configured(self):
        self.check(posture(mode="entra", has_token=True), "denied", "auth_not_configured", 401, "/posture")

    def test_invalid_org(self):
        self.check(posture("../../x"), "denied", "invalid_org", 400, "/posture")

    def test_unknown_org(self):
        self.check(posture("org-zzz"), "denied", "unknown_org", 404, "/posture")

    def test_invalid_key(self):
        self.check(controls("vuln-mgmt' OR 1=1 --"), "denied", "invalid_key", 400, "/indicators/{key}/controls")

    def test_unknown_indicator(self):
        self.check(controls("nao-existe"), "denied", "unknown_indicator", 404, "/indicators/{key}/controls")

    def test_auth_mode_is_effective_mode(self):
        _, evs = posture(mode="qualquer-coisa")
        self.assertEqual(evs[0]["authMode"], "entra")
        _, evs = posture(mode=DEV)
        self.assertEqual(evs[0]["authMode"], DEV)

    def test_unexpected_error_emits_no_authz_event(self):
        def broken():
            raise RuntimeError("falha interna")

        logger = logging.getLogger("authz")
        with self.assertNoLogs(logger, level="INFO"), self.assertLogs(level="ERROR"):
            status, _ = dispatch(lambda: routes.posture({"org": "org-a"}, broken, DEV))
        self.assertEqual(status, 500)


class SanitizationTests(unittest.TestCase):
    def test_sanitize_org(self):
        cases = {
            "org-a": "org-a",
            "ORG-A": "???-?",
            "../../x": "??????x",
            "org-a' OR 1=1 --": "org-a?????1?1?--",
            "org-a\n{\"x\":1}": "org-a???x??1?",
            "": "",
            None: "",
            "a" * 100: "a" * 40,
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(audit.sanitize_org(raw), expected)

    def test_org_in_event_is_sanitized_and_truncated(self):
        payload = "org-" + "<script>alert(1)</script>" * 5
        _, evs = posture(payload)
        self.assertLessEqual(len(evs[0]["org"]), 40)
        self.assertRegex(evs[0]["org"], r"^[a-z0-9?-]*$")

    def test_client_ip(self):
        cases = {
            "203.0.113.7:51234": "203.0.113.7",
            "203.0.113.7": "203.0.113.7",
            "203.0.113.7:51234, 10.0.0.1": "203.0.113.7",
            "[2001:db8::1]:443": "2001:db8::1",
            "2001:db8::1": "2001:db8::1",
            "nao-e-ip": "unknown",
            "1.2.3.4' OR 1=1": "unknown",
            "": "unknown",
            None: "unknown",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(audit.client_ip(raw), expected)


class NoSecretsTests(unittest.TestCase):
    """Chama a Function de verdade (function_app) com cabeçalhos sensíveis."""

    def test_headers_token_query_never_logged(self):
        import azure.functions as func

        import function_app

        function_app.get_container = test_api.get_fake
        function_app.auth_mode = lambda: DEV
        secrets = ["SECRET-TOKEN-123", "SECRET-COOKIE-456", "SECRET-QS-789"]
        req = func.HttpRequest(
            method="GET",
            url="https://example/api/posture?org=org-a&token=SECRET-QS-789",
            headers={
                "Authorization": "Bearer SECRET-TOKEN-123",
                "Cookie": "session=SECRET-COOKIE-456",
                "X-Forwarded-For": "203.0.113.7:50000",
            },
            params={"org": "org-a", "token": "SECRET-QS-789"},
            body=b"",
        )
        with self.assertLogs(level="DEBUG") as cm:
            resp = function_app.posture(req)
        self.assertEqual(resp.status_code, 200)
        everything = "\n".join(r.getMessage() for r in cm.records)
        for s in secrets:
            self.assertNotIn(s, everything)
        authz = [r.getMessage() for r in cm.records if r.getMessage().startswith(audit.PREFIX)]
        self.assertEqual(len(authz), 1)
        e = json.loads(authz[0][len(audit.PREFIX):])
        self.assertEqual(set(e), {"route", "authMode", "outcome", "reason", "org", "status", "ip"})
        self.assertEqual(e["ip"], "203.0.113.7")


if __name__ == "__main__":
    unittest.main()
