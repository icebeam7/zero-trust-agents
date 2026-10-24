import sys,os
from pathlib import Path
from azure.core.exceptions import HttpResponseError
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.agents import search_docs,forbidden_write_test
from dotenv import load_dotenv
load_dotenv()
role=os.getenv('ROLE_TEST','analyst')
if role=='analyst':
    print('Reading Contoso Search documents:',search_docs('contoso','revenue'))
    try:
        forbidden_write_test()
        raise SystemExit('SECURITY FAILURE: analyst wrote to reports container')
    except HttpResponseError as exc:
        print('PASS: analyst denied Blob write:',exc.status_code)
else:
    try:
        search_docs('contoso','revenue')
        raise SystemExit('SECURITY FAILURE: reporter read search index')
    except HttpResponseError as exc:
        print('PASS: reporter denied Search read:',exc.status_code)
