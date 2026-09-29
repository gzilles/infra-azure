"""Seed do Cosmos DB a partir de apps/web/mock-data.js (a fonte de verdade da tela).

Uso:
    COSMOS_ENDPOINT=https://... python seed.py            # upsert de todos os documentos
    COSMOS_ENDPOINT=https://... python seed.py --check    # só lê: contagem por organização e tipo
    COSMOS_ENDPOINT=https://... python seed.py --prune    # lista documentos que não vêm do mock
    COSMOS_ENDPOINT=https://... python seed.py --prune --apply   # e os apaga

Autentica com DefaultAzureCredential (o `az login` do operador), sem chaves.
"""

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

MOCK_FILE = Path(__file__).resolve().parents[2] / "apps" / "web" / "mock-data.js"


def load_mock(path: Path = MOCK_FILE) -> dict:
    """Converte o objeto literal de mock-data.js em JSON.

    O arquivo é JS simples: comentários //, chaves sem aspas e vírgulas finais.
    Qualquer coisa fora disso faz o json.loads falhar alto, o que é o desejado.
    """
    src = path.read_text(encoding="utf-8")
    src = re.sub(r"(?m)^\s*//.*$", "", src)
    start, end = src.index("{"), src.rindex("}")
    body = src[start : end + 1]
    body = re.sub(r"([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:", r'\1"\2":', body)
    body = re.sub(r",\s*([}\]])", r"\1", body)
    return json.loads(body)


def documents_for(org_id: str, data: dict) -> list[dict]:
    posture = data["posture"]
    docs = [
        {
            "id": "summary",
            "organizationId": org_id,
            "type": "summary",
            "organizationName": posture["organization"]["name"],
            "score": posture["score"],
            "previousScore": posture["previousScore"],
            "updatedAt": posture["updatedAt"],
        }
    ]
    for order, ind in enumerate(posture["indicators"], start=1):
        docs.append(
            {
                "id": f"indicator:{ind['key']}",
                "organizationId": org_id,
                "type": "indicator",
                "key": ind["key"],
                "name": ind["name"],
                "score": ind["score"],
                "previousScore": ind["previousScore"],
                "trend": ind["trend"],
                "order": order,
            }
        )
    for key, controls in data["controls"].items():
        for c in controls:
            docs.append(
                {
                    "id": f"control:{c['id']}",
                    "organizationId": org_id,
                    "type": "control",
                    "indicatorKey": key,
                    "controlId": c["id"],
                    "name": c["name"],
                    "owner": c["owner"],
                    "dueDate": c["dueDate"],
                    "status": c["status"],
                }
            )
    return docs


def all_documents(mock: dict) -> dict[str, list[dict]]:
    return {org_id: documents_for(org_id, data) for org_id, data in mock.items()}


def container_client():
    from azure.cosmos import CosmosClient
    from azure.identity import DefaultAzureCredential

    endpoint = os.environ.get("COSMOS_ENDPOINT")
    if not endpoint:
        sys.exit("Defina COSMOS_ENDPOINT (terraform -chdir=envs/dev output -raw cosmos_endpoint).")
    database = os.environ.get("COSMOS_DATABASE", "posture")
    container = os.environ.get("COSMOS_CONTAINER", "posture")
    client = CosmosClient(endpoint, credential=DefaultAzureCredential())
    return client.get_database_client(database).get_container_client(container)


def existing(container, org_id: str) -> list[dict]:
    return list(
        container.query_items(
            "SELECT c.id, c.type FROM c WHERE c.organizationId = @org",
            parameters=[{"name": "@org", "value": org_id}],
            partition_key=org_id,
        )
    )


def seed(container, docs_by_org: dict) -> None:
    for org_id, docs in docs_by_org.items():
        for doc in docs:
            container.upsert_item(doc)
        print(f"{org_id}: {len(docs)} documentos gravados (upsert)")


def check(container, docs_by_org: dict) -> None:
    print(f"{'organização':<12} {'summary':>8} {'indicator':>10} {'control':>8} {'outros':>7} {'esperado':>9}")
    for org_id, docs in docs_by_org.items():
        got = Counter(d.get("type") for d in existing(container, org_id))
        other = sum(n for t, n in got.items() if t not in ("summary", "indicator", "control"))
        print(
            f"{org_id:<12} {got['summary']:>8} {got['indicator']:>10} {got['control']:>8} {other:>7} {len(docs):>9}"
        )


def prune(container, docs_by_org: dict, apply: bool) -> None:
    for org_id, docs in docs_by_org.items():
        wanted = {d["id"] for d in docs}
        stale = [d for d in existing(container, org_id) if d["id"] not in wanted]
        for d in stale:
            print(f"{org_id}: {'apagando' if apply else 'sobraria'} {d['id']} (type={d.get('type')})")
            if apply:
                container.delete_item(d["id"], partition_key=org_id)
        if not stale:
            print(f"{org_id}: nenhum documento fora do mock")


if __name__ == "__main__":
    docs_by_org = all_documents(load_mock())
    c = container_client()
    if "--check" in sys.argv:
        check(c, docs_by_org)
    elif "--prune" in sys.argv:
        prune(c, docs_by_org, apply="--apply" in sys.argv)
    else:
        seed(c, docs_by_org)
