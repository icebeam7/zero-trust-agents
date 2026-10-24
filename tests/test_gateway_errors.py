import asyncio
import inspect

from fastapi import HTTPException

from app import agents, main


def test_model_agent_uses_async_openai_api_key_provider(monkeypatch):
    captured = {}

    class FakeAsyncOpenAI:
        def __init__(self, *, base_url, api_key):
            captured['base_url'] = base_url
            captured['api_key'] = api_key

    class FakeAgent:
        def __init__(self, *, client, name, instructions):
            captured['client'] = client
            captured['name'] = name
            captured['instructions'] = instructions

    class FakeChatClient:
        def __init__(self, *, model, async_client):
            captured['model'] = model
            captured['async_client'] = async_client

    monkeypatch.setattr(agents, 'require', lambda name: 'https://example.openai.azure.com/openai/v1/' if name == 'AZURE_OPENAI_BASE_URL' else 'dep')
    monkeypatch.setattr(agents, 'credential', lambda: type('Cred', (), {'get_token': lambda self, scope: type('Token', (), {'token': 'abc'})()})())
    monkeypatch.setattr(agents, 'os', type('Os', (), {'getenv': lambda self, key, default=None: 'gpt-4.1-mini' if key == 'AZURE_OPENAI_DEPLOYMENT' else default})())
    monkeypatch.setattr(agents, 'Agent', FakeAgent)

    import agent_framework.openai as agent_openai
    monkeypatch.setattr(agent_openai, 'OpenAIChatCompletionClient', FakeChatClient)

    import openai
    monkeypatch.setattr(openai, 'AsyncOpenAI', FakeAsyncOpenAI)

    result = agents.model_agent('demo', 'test instructions')
    assert captured['base_url'] == 'https://example.openai.azure.com/openai/v1/'
    assert asyncio.iscoroutinefunction(captured['api_key'])
    assert result is not None


def test_workload_token_missing_env_surfaces_clear_error(monkeypatch):
    monkeypatch.setattr(main, 'require', lambda name: (_ for _ in ()).throw(RuntimeError(f'Missing environment variable: {name}')))
    monkeypatch.setattr(main, 'credential', lambda: object())

    try:
        main.workload_token()
        raise AssertionError('Expected HTTPException to be raised')
    except HTTPException as exc:
        assert 'Unable to acquire the workload token' in str(exc.detail)


def test_call_worker_errors_are_wrapped_with_details(monkeypatch):
    monkeypatch.setattr(main, 'workload_token', lambda: 'fake-token')

    class FakeResponse:
        status_code = 500
        reason_phrase = 'Internal Server Error'
        text = 'downstream failed'

        def raise_for_status(self):
            raise main.httpx.HTTPStatusError('boom', request=None, response=main.httpx.Response(500, text='downstream failed'))

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, tb):
            return False

        async def post(self, *args, **kwargs):
            return FakeResponse()

    monkeypatch.setattr(main.httpx, 'AsyncClient', FakeAsyncClient)

    async def run():
        try:
            await main.call_worker('https://example.internal', {'tenant': 'contoso'})
            raise AssertionError('Expected HTTPException to be raised')
        except HTTPException as exc:
            assert 'Worker call failed' in str(exc.detail)

    asyncio.run(run())
