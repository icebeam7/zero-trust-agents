import os
import json
import httpx
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel
from azure.identity import get_bearer_token_provider
from azure.core.exceptions import HttpResponseError
from .common import credential, require
from .security import verify_service_token, tenant_guard
from .agents import analyze, make_report, write_report, forbidden_write_test, search_docs

app = FastAPI(title='Zero Trust Multi-Agent Azure Demo')
ROLE = os.getenv('SERVICE_ROLE', 'gateway')

class Ask(BaseModel):
    tenant: str
    question: str

class ReportRequest(BaseModel):
    tenant: str
    analysis: str

@app.get('/health')
def health():
    return {'status':'up','service':ROLE}

def workload_token():
    # Azure Entra application permission to the internal API. Assigned to gateway identity.
    try:
        app_id = require('INTERNAL_API_APP_ID')
        tenant_id = require('AZURE_TENANT_ID')
        if not app_id or not tenant_id:
            raise RuntimeError('Missing required workload identity configuration')
        return credential().get_token(f'api://{app_id}/.default').token
    except Exception as exc:
        raise HTTPException(
            500,
            'Unable to acquire the workload token. Check AZURE_TENANT_ID, INTERNAL_API_APP_ID, and that the app-role assignment has propagated.'
        ) from exc

async def call_worker(url: str, payload: dict):
    try:
        async with httpx.AsyncClient(timeout=120) as client:
            response = await client.post(url, json=payload, headers={'Authorization':f'Bearer {workload_token()}'})
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                detail = exc.response.text.strip() or exc.response.reason_phrase
                raise HTTPException(502, f'Worker call failed for {url}: {detail}') from exc
            return response.json()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(502, f'Cannot reach worker at {url}. Check the internal URL and the Entra token setup.') from exc

@app.post('/internal/analyze')
async def internal_analyze(body: Ask, authorization: str = Header(default='')):
    if ROLE != 'analyst': raise HTTPException(404)
    verify_service_token(authorization)
    return await analyze(body.tenant, body.question)

@app.post('/internal/report')
async def internal_report(body: ReportRequest, authorization: str = Header(default='')):
    if ROLE != 'reporter': raise HTTPException(404)
    verify_service_token(authorization)
    result = await make_report(body.tenant, body.analysis)
    path = write_report(body.tenant, result)
    return {'report':result,'blob':path}

@app.post('/demo/run')
async def run(body: Ask, authorization: str = Header(default='')):
    if ROLE != 'gateway': raise HTTPException(404)
    # For genuine public deployment, configure built-in ACA Easy Auth and validate
    # the authenticated user's token in this route, mapping user -> allowed tenant.
    # Gateway demo access via CLI-forwarded loopback only (instructions in README).
    if os.getenv('ALLOW_LOCAL_DEMO') != 'yes':
        raise HTTPException(403, 'Interactive demo disabled until user auth is configured')
    tenant_guard(body.tenant, os.getenv('DEMO_TENANT','contoso'))
    analysis = await call_worker(require('ANALYST_URL').rstrip('/')+'/internal/analyze', body.model_dump())
    report = await call_worker(require('REPORTER_URL').rstrip('/')+'/internal/report', {'tenant':body.tenant,'analysis':analysis['answer']})
    return {'analysis':analysis,'report':report}

@app.post('/demo/cross-tenant')
async def cross_tenant(body: Ask):
    if ROLE != 'gateway': raise HTTPException(404)
    tenant_guard(body.tenant, os.getenv('DEMO_TENANT','contoso'))
    return {'unexpected':'allowed'}

@app.post('/internal/forbidden-write')
def forbidden_write(authorization: str = Header(default='')):
    if ROLE != 'analyst': raise HTTPException(404)
    verify_service_token(authorization)
    try:
        forbidden_write_test()
        return {'WARNING':'Unauthorized write succeeded. Check IAM configuration!'}
    except HttpResponseError as e:
        return {'expected':'storage authorization denied', 'http_status':e.status_code, 'error_code':getattr(e,'error_code',None)}

@app.post('/internal/forbidden-search')
def forbidden_search(authorization: str = Header(default='')):
    if ROLE != 'reporter': raise HTTPException(404)
    verify_service_token(authorization)
    try:
        search_docs('contoso','revenue')
        return {'WARNING':'Unauthorized query succeeded. Check IAM configuration!'}
    except HttpResponseError as e:
        return {'expected':'search authorization denied', 'http_status':e.status_code, 'error_code':getattr(e,'error_code',None)}
