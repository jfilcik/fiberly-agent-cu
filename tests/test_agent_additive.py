"""Unit tests for additive guarantees in fibey.agent.agent.

These tests assert that with all CU-related env vars unset the agent
module behaves like ``main`` — the CU and Foundry IQ extensions are
strictly opt-in.
"""
from __future__ import annotations

import importlib
import sys

import pytest


CU_ENV_VARS = [
    "AZURE_CONTENTUNDERSTANDING_ENDPOINT",
    "FOUNDRY_IQ_MINIMAL_MCP_URL",
    "FOUNDRY_IQ_STANDARD_MCP_URL",
    "CU_VERBOSE_LOGGING",
    "AGENT_MODE",
    "TOOLBOX_MCP_URL",
]


@pytest.fixture
def clean_env(monkeypatch):
    for k in CU_ENV_VARS:
        monkeypatch.delenv(k, raising=False)
    # force re-import so module-level env reads happen with clean env
    sys.modules.pop("fibey.agent.agent", None)
    return monkeypatch


def _import_agent():
    return importlib.import_module("fibey.agent.agent")


def test_defaults_match_main(clean_env):
    a = _import_agent()
    assert a._AGENT_MODE == "local"
    assert a._LOCAL_DIRECT is False
    assert a._CU_ENABLED is False
    assert a._CU_FOUNDRY_IQ_ENABLED is False
    assert a._CU_VERBOSE_LOGGING is False


def test_base_prompt_has_no_cu_sections(clean_env):
    a = _import_agent()
    prompt = a._load_system_prompt(cu_active=False)
    assert "Document Upload" not in prompt
    assert "Work Order Extraction" not in prompt


def test_cu_prompt_appended_only_when_active(clean_env):
    a = _import_agent()
    prompt = a._load_system_prompt(cu_active=True)
    assert "Document Upload" in prompt
    assert "Work Order Extraction" in prompt


def test_local_direct_opt_in(clean_env, monkeypatch):
    monkeypatch.setenv("AGENT_MODE", "local-direct")
    sys.modules.pop("fibey.agent.agent", None)
    a = _import_agent()
    assert a._LOCAL_DIRECT is True


def test_cu_flag_driven_by_endpoint(clean_env, monkeypatch):
    monkeypatch.setenv("AZURE_CONTENTUNDERSTANDING_ENDPOINT", "https://example.cognitiveservices.azure.com")
    sys.modules.pop("fibey.agent.agent", None)
    a = _import_agent()
    assert a._CU_ENABLED is True
    assert a._CU_FOUNDRY_IQ_ENABLED is False


def test_iq_flag_requires_both_urls(clean_env, monkeypatch):
    monkeypatch.setenv("FOUNDRY_IQ_MINIMAL_MCP_URL", "https://example/mcp/min")
    sys.modules.pop("fibey.agent.agent", None)
    a = _import_agent()
    assert a._CU_FOUNDRY_IQ_ENABLED is False

    monkeypatch.setenv("FOUNDRY_IQ_STANDARD_MCP_URL", "https://example/mcp/std")
    sys.modules.pop("fibey.agent.agent", None)
    a = _import_agent()
    assert a._CU_FOUNDRY_IQ_ENABLED is True
