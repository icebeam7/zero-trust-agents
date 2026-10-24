"""Validate application tokens at agent API boundaries; never trust X-Tenant from public callers."""
import os
import jwt
from jwt import PyJWKClient
from fastapi import HTTPException
from .common import require

def verify_service_token(authorization: str, expected_role: str = 'invoke') -> dict:
    if not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Bearer token required')
    tenant_id = require('AZURE_TENANT_ID')
    audience = require('INTERNAL_API_APP_ID')
    token = authorization.split(' ', 1)[1]
    try:
        jwks = PyJWKClient(f'https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys')
        key = jwks.get_signing_key_from_jwt(token)
        claims = jwt.decode(token, key.key, algorithms=['RS256'], audience=[audience, f'api://{audience}'], options={'verify_iss': False})
        if claims.get('tid') != tenant_id:
            raise ValueError('Invalid issuer tenant')
        issuer = claims.get('iss', '')
        valid = {f'https://login.microsoftonline.com/{tenant_id}/v2.0', f'https://sts.windows.net/{tenant_id}/'}
        if issuer not in valid:
            raise ValueError('Invalid issuer')
        if expected_role not in claims.get('roles', []):
            raise ValueError('Required application role missing')
        return claims
    except Exception as exc:
        raise HTTPException(403, 'Invalid workload token or missing app role') from exc

def tenant_guard(requested: str, authorized: str):
    if requested != authorized:
        raise HTTPException(403, 'Cross-tenant request denied')
