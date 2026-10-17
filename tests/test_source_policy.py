from source_policy import source_allowed

def test_production_is_closed_without_reviewed_sources(monkeypatch):
    monkeypatch.setenv('NEWS_DEPLOYMENT_MODE', 'production')
    monkeypatch.delenv('NEWS_SOURCE_ALLOWLIST', raising=False)
    assert not source_allowed('guardian')
    assert not source_allowed('youtube')

def test_allowlist_does_not_approve_other_sources(monkeypatch):
    monkeypatch.setenv('NEWS_DEPLOYMENT_MODE', 'production')
    monkeypatch.setenv('NEWS_SOURCE_ALLOWLIST', 'nasa_rss, gov_alerts')
    assert source_allowed('nasa_rss')
    assert source_allowed('gov_alerts')
    assert not source_allowed('rss_outlets')
    assert not source_allowed('guardian')

def test_development_preserves_existing_integration(monkeypatch):
    monkeypatch.delenv('NEWS_DEPLOYMENT_MODE', raising=False)
    assert source_allowed('guardian')
