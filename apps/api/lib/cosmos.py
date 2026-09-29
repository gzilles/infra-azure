import os

_container = None


def get_container():
    """Cliente do Cosmos criado uma vez por instância e reaproveitado entre invocações."""
    global _container
    if _container is None:
        from azure.cosmos import CosmosClient
        from azure.identity import DefaultAzureCredential

        client = CosmosClient(os.environ["COSMOS_ENDPOINT"], credential=DefaultAzureCredential())
        _container = client.get_database_client(os.environ["COSMOS_DATABASE"]).get_container_client(
            os.environ["COSMOS_CONTAINER"]
        )
    return _container
