"""Seed de dados fictícios do Security Posture Dashboard no Cosmos DB.

Uso:
    COSMOS_ENDPOINT=https://... python seed.py           # grava (upsert) as duas organizações
    COSMOS_ENDPOINT=https://... python seed.py --check   # só lê e conta documentos por organização

Autentica com DefaultAzureCredential (ex.: o `az login` do operador). Não usa chaves:
a conta tem local_authentication_disabled = true.
"""

import os
import sys
from datetime import date, datetime, timedelta, timezone

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

TODAY = date.today()


def due(days_from_today: int) -> str:
    return (TODAY + timedelta(days=days_from_today)).isoformat()


def control(cid: str, name: str, status: str, due_in_days: int, owner: str) -> dict:
    return {"id": cid, "name": name, "status": status, "dueDate": due(due_in_days), "owner": owner}


def indicator_status(score: int) -> str:
    if score >= 80:
        return "on_track"
    if score >= 60:
        return "at_risk"
    return "critical"


# Cada organização: 5 indicadores com seus controles. Status de controle:
# compliant | in_progress | overdue (prazo vencido sem conclusão).
ORGANIZATIONS = {
    "org-a": {
        "Vulnerability Management": (
            52,
            [
                control("VM-01", "Patch de vulnerabilidades críticas em até 15 dias", "overdue", -21, "infra"),
                control("VM-02", "Varredura autenticada mensal dos servidores", "overdue", -9, "secops"),
                control("VM-03", "Inventário de ativos expostos à internet", "overdue", -4, "infra"),
                control("VM-04", "SLA de correção por severidade documentado", "compliant", -30, "secops"),
            ],
        ),
        "Identity & Access Management": (
            78,
            [
                control("IAM-01", "MFA para todos os usuários", "compliant", -60, "identidade"),
                control("IAM-02", "Revisão trimestral de acessos privilegiados", "in_progress", 12, "identidade"),
                control("IAM-03", "Desprovisionamento em até 24h após desligamento", "compliant", -15, "rh"),
            ],
        ),
        "Data Protection": (
            84,
            [
                control("DP-01", "Criptografia em repouso nos bancos de dados", "compliant", -90, "dados"),
                control("DP-02", "Classificação de dados sensíveis", "in_progress", 20, "dados"),
            ],
        ),
        "Incident Response": (
            70,
            [
                control("IR-01", "Plano de resposta a incidentes aprovado", "compliant", -120, "secops"),
                control("IR-02", "Exercício de mesa semestral", "in_progress", 30, "secops"),
                control("IR-03", "Retenção de logs de auditoria por 1 ano", "compliant", -45, "infra"),
            ],
        ),
        "Security Awareness": (
            88,
            [
                control("SA-01", "Treinamento anual de segurança concluído", "compliant", -10, "rh"),
                control("SA-02", "Simulação de phishing trimestral", "compliant", -5, "secops"),
            ],
        ),
    },
    "org-b": {
        "Vulnerability Management": (
            86,
            [
                control("VM-01", "Patch de vulnerabilidades críticas em até 15 dias", "compliant", -3, "infra"),
                control("VM-02", "Varredura autenticada mensal dos servidores", "compliant", -12, "secops"),
                control("VM-03", "Inventário de ativos expostos à internet", "in_progress", 8, "infra"),
            ],
        ),
        "Identity & Access Management": (
            64,
            [
                control("IAM-01", "MFA para todos os usuários", "in_progress", 14, "identidade"),
                control("IAM-02", "Revisão trimestral de acessos privilegiados", "overdue", -6, "identidade"),
            ],
        ),
        "Data Protection": (
            91,
            [
                control("DP-01", "Criptografia em repouso nos bancos de dados", "compliant", -80, "dados"),
                control("DP-02", "Classificação de dados sensíveis", "compliant", -25, "dados"),
            ],
        ),
        "Incident Response": (
            75,
            [
                control("IR-01", "Plano de resposta a incidentes aprovado", "compliant", -200, "secops"),
                control("IR-02", "Exercício de mesa semestral", "in_progress", 40, "secops"),
            ],
        ),
        "Security Awareness": (
            69,
            [
                control("SA-01", "Treinamento anual de segurança concluído", "in_progress", 18, "rh"),
                control("SA-02", "Simulação de phishing trimestral", "compliant", -20, "secops"),
            ],
        ),
    },
}


def slug(name: str) -> str:
    return name.lower().replace("&", "and").replace(" ", "-").replace("--", "-")


def documents_for(org_id: str, indicators: dict) -> list[dict]:
    now = datetime.now(timezone.utc).isoformat()
    docs = []
    scores = []
    for name, (score, controls) in indicators.items():
        scores.append(score)
        docs.append(
            {
                "id": f"indicator-{slug(name)}",
                "organizationId": org_id,
                "type": "indicator",
                "name": name,
                "score": score,
                "status": indicator_status(score),
                "overdueControls": sum(1 for c in controls if c["status"] == "overdue"),
                "controls": controls,
                "updatedAt": now,
            }
        )
    consolidated = round(sum(scores) / len(scores))
    docs.append(
        {
            "id": "posture-score",
            "organizationId": org_id,
            "type": "postureScore",
            "score": consolidated,
            "status": indicator_status(consolidated),
            "indicatorCount": len(indicators),
            "updatedAt": now,
        }
    )
    return docs


def container_client():
    endpoint = os.environ.get("COSMOS_ENDPOINT")
    if not endpoint:
        sys.exit("Defina COSMOS_ENDPOINT (terraform -chdir=envs/dev output -raw cosmos_endpoint).")
    database = os.environ.get("COSMOS_DATABASE", "posture")
    container = os.environ.get("COSMOS_CONTAINER", "posture")
    client = CosmosClient(endpoint, credential=DefaultAzureCredential())
    return client.get_database_client(database).get_container_client(container)


def seed(container) -> None:
    for org_id, indicators in ORGANIZATIONS.items():
        docs = documents_for(org_id, indicators)
        for doc in docs:
            container.upsert_item(doc)
        print(f"{org_id}: {len(docs)} documentos gravados")


def check(container) -> None:
    for org_id in ORGANIZATIONS:
        items = list(
            container.query_items(
                "SELECT c.id, c.type FROM c WHERE c.organizationId = @org",
                parameters=[{"name": "@org", "value": org_id}],
                partition_key=org_id,
            )
        )
        print(f"{org_id}: {len(items)} documentos")


if __name__ == "__main__":
    c = container_client()
    check(c) if "--check" in sys.argv else seed(c)
