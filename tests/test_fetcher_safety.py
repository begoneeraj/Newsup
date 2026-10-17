import asyncio
from unittest.mock import AsyncMock, MagicMock

import aiohttp

from fetchers import guardian, mediastack


def test_mediastack_uses_https_and_conservative_free_quota():
    assert mediastack.MEDIASTACK_URL.startswith('https://')
    assert mediastack.DAILY_LIMIT <= mediastack.MEDIASTACK_MONTHLY_LIMIT // 31


def test_mediastack_stops_before_request_when_quota_exhausted(monkeypatch):
    monkeypatch.setenv('MEDIASTACK_API_KEY', 'test-private-key')
    monkeypatch.setattr(mediastack, 'can_fetch', lambda *_: False)
    session = MagicMock()
    monkeypatch.setattr(mediastack.aiohttp, 'ClientSession', session)
    assert asyncio.run(mediastack.fetch_all_mediastack()) == []
    session.assert_not_called()


def test_mediastack_does_not_log_key_from_network_exception(monkeypatch, caplog):
    monkeypatch.setenv('MEDIASTACK_API_KEY', 'test-private-key')
    monkeypatch.setattr(mediastack, 'can_fetch', lambda *_: True)
    session = MagicMock()
    session.get.side_effect = aiohttp.ClientError('url?access_key=test-private-key')
    context = MagicMock()
    context.__aenter__ = AsyncMock(return_value=session)
    context.__aexit__ = AsyncMock(return_value=False)
    monkeypatch.setattr(mediastack.aiohttp, 'ClientSession', lambda: context)
    assert asyncio.run(mediastack.fetch_all_mediastack()) == []
    assert 'test-private-key' not in caplog.text
    assert 'ClientError' in caplog.text


def test_guardian_spaces_section_requests(monkeypatch):
    monkeypatch.setenv('THE_GUARDIAN_API_KEY', 'test-private-key')
    fetch = AsyncMock(return_value=[])
    pause = AsyncMock()
    monkeypatch.setattr(guardian, '_fetch_section', fetch)
    monkeypatch.setattr(guardian.asyncio, 'sleep', pause)
    assert asyncio.run(guardian.fetch_all_guardian(['world', 'technology', 'business'])) == []
    assert fetch.await_count == 3
    assert pause.await_count == 2
    assert all(call.args[0] >= 1 for call in pause.await_args_list)
