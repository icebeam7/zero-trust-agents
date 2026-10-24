import os
from functools import lru_cache
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from dotenv import load_dotenv
load_dotenv()

def credential():
    cid = os.getenv('AZURE_CLIENT_ID')
    return ManagedIdentityCredential(client_id=cid) if cid else DefaultAzureCredential(exclude_interactive_browser_credential=True)

def require(name):
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f'Missing environment variable: {name}')
    return value
