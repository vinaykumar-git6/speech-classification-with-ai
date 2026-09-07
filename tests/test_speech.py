import json
from unittest.mock import Mock

import httpx
import pytest

from audio_pipeline.speech import SpeechClient, SpeechError

API_VERSION = "2025-10-15"


class FakeCredential:
    def get_token(self, *scopes: str) -> Mock:
        return Mock(token="token")


def response(status_code: int, text: str = "") -> httpx.Response:
    return httpx.Response(
        status_code,
        text=text,
        request=httpx.Request("GET", "https://speech.example.test/job"),
    )


def json_response(payload: dict) -> httpx.Response:
    return httpx.Response(
        200,
        json=payload,
        request=httpx.Request("POST", "https://speech.example.test/transcribe"),
    )


def test_speech_request_retries_throttling(monkeypatch: pytest.MonkeyPatch) -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()
    client._client.request.side_effect = [response(429), response(503), response(200)]
    sleep = Mock()
    monkeypatch.setattr("audio_pipeline.speech.time.sleep", sleep)

    result = client._request("GET", "https://speech.example.test/job")

    assert result.status_code == 200
    assert client._client.request.call_count == 3
    assert [call.args[0] for call in sleep.call_args_list] == [1.0, 2.0]


def test_speech_request_stops_after_retry_budget(monkeypatch: pytest.MonkeyPatch) -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()
    client._client.request.return_value = response(503, "unavailable")
    monkeypatch.setattr("audio_pipeline.speech.time.sleep", Mock())

    with pytest.raises(SpeechError, match="failed after retries"):
        client._request("GET", "https://speech.example.test/job")

    assert client._client.request.call_count == 6


def test_transcribe_uploads_audio_and_returns_combined_text() -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()
    client._client.request.return_value = json_response(
        {
            "durationMilliseconds": 2000,
            "combinedPhrases": [{"channel": 0, "text": "Please cancel my order."}],
        }
    )

    text, duration = client.transcribe(b"audio-bytes", "call.wav", "en-US")

    assert text == "Please cancel my order."
    assert duration == 2000
    args, kwargs = client._client.request.call_args
    assert args[0] == "POST"
    assert args[1] == (
        f"https://speech.example.test/speechtotext/transcriptions:transcribe"
        f"?api-version={API_VERSION}"
    )
    assert kwargs["files"]["audio"] == ("call.wav", b"audio-bytes", "application/octet-stream")
    assert json.loads(kwargs["data"]["definition"])["locales"] == ["en-US"]


def test_transcribe_omits_locale_for_language_identification() -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()
    client._client.request.return_value = json_response(
        {"durationMilliseconds": 10, "combinedPhrases": [{"text": "Hello"}]}
    )

    client.transcribe(b"audio-bytes", "call.wav", None)

    _, kwargs = client._client.request.call_args
    assert json.loads(kwargs["data"]["definition"])["locales"] == []


def test_transcribe_rejects_empty_result() -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()
    client._client.request.return_value = json_response(
        {"durationMilliseconds": 0, "combinedPhrases": []}
    )

    with pytest.raises(SpeechError, match="no recognized text"):
        client.transcribe(b"audio-bytes", "call.wav", "en-US")


def test_transcribe_rejects_oversized_audio() -> None:
    client = SpeechClient("https://speech.example.test", API_VERSION, FakeCredential())
    client._client = Mock()

    with pytest.raises(SpeechError, match="fast transcription limit"):
        client.transcribe(b"x" * (250 * 1024 * 1024 + 1), "call.wav", "en-US")

    client._client.request.assert_not_called()