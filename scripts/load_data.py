"""Upload real documents to Blob and index them in Azure AI Search, identity-only."""
import os,sys
from pathlib import Path
from azure.storage.blob import BlobServiceClient
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import SearchIndex, SimpleField, SearchableField, SearchFieldDataType
from dotenv import load_dotenv
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.common import credential, require
load_dotenv()
root=Path(__file__).resolve().parents[1]/'docs'
storage=BlobServiceClient(account_url=require('AZURE_BLOB_ACCOUNT_URL'), credential=credential())
index_name=os.getenv('AZURE_SEARCH_INDEX','company-knowledge')
endpoint=require('AZURE_SEARCH_ENDPOINT')
index_client=SearchIndexClient(endpoint,credential())
fields=[SimpleField(name='id',type=SearchFieldDataType.String,key=True),
        SimpleField(name='tenant',type=SearchFieldDataType.String,filterable=True),
        SearchableField(name='title',type=SearchFieldDataType.String),
        SearchableField(name='content',type=SearchFieldDataType.String)]
index_client.create_or_update_index(SearchIndex(name=index_name,fields=fields))
records=[]
for tenant in ['contoso','fabrikam']:
    for file in sorted((root/tenant).glob('*.txt')):
        content=file.read_text()
        storage.get_blob_client(f'{tenant}-docs',file.name).upload_blob(content.encode(),overwrite=True)
        records.append({'id':f'{tenant}-{file.stem}','tenant':tenant,'title':file.name,'content':content})
client=SearchClient(endpoint,index_name,credential())
result=client.upload_documents(records)
for r in result: print(r.key, 'indexed=',r.succeeded)
if not all(r.succeeded for r in result): raise SystemExit('Partial indexing failure')
print('Real Blob documents uploaded and real Search index populated with tenant filter.')
