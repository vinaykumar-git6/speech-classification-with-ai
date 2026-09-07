from __future__ import annotations

import json
import time
from typing import Any

import httpx
from azure.core.credentials import TokenCredential

# Fast transcription rejects audio longer than 2 hours or larger than 250 MB.
MAX_AUDIO_BYTES = 250 * 1024 * 1024


class SpeechError(RuntimeError):
    pass


class SpeechClient:
    def __init__(
        self,
        endpoint: str,
        api_version: str,
        credential: TokenCredential,
        api_key: str | None = None,
        timeout_seconds: float = 600,
    ) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._api_version = api_version
        self._credential = credential
        self._api_key = api_key
        self._client = httpx.Client(timeout=timeout_seconds)

    def _headers(self) -> dict[str, str]:
        if self._api_key:
            return {"Ocp-Apim-Subscription-Key": self._api_key}
        token = self._credential.get_token("https://cognitiveservices.azure.com/.default")
        return {"Authorization": f"Bearer {token.token}"}

    def _request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        delay = 1.0
        for attempt in range(6):
            response = self._client.request(method, url, headers=self._headers(), **kwargs)
            if response.status_code not in {429, 500, 502, 503, 504}:
                response.raise_for_status()
                return response
            if attempt == 5:
                raise SpeechError(
                    f"Speech API failed after retries: {response.status_code} {response.text[:500]}"
                )
            retry_after = response.headers.get("retry-after")
            time.sleep(float(retry_after) if retry_after else delay)
            delay = min(delay * 2, 30)
        raise AssertionError("unreachable")

    def transcribe(
        self,
        audio: bytes,
        filename: str,
        locale: str | None = None,
        profanity_filter_mode: str = "Masked",
    ) -> tuple[str, int]:
        """Transcribe audio synchronously, returning the combined text and duration."""
        if not audio:
            raise SpeechError("Cannot transcribe an empty audio file")
        if len(audio) > MAX_AUDIO_BYTES:
            raise SpeechError(
                f"Audio is {len(audio)} bytes, above the {MAX_AUDIO_BYTES} byte "
                "fast transcription limit"
            )

        definition = {
            "locales": [locale] if locale else [],
            "profanityFilterMode": profanity_filter_mode,
        }
        response = self._request(
            "POST",
            f"{self._endpoint}/speechtotext/transcriptions:transcribe"
            f"?api-version={self._api_version}",
            files={"audio": (filename, audio, "application/octet-stream")},
            data={"definition": json.dumps(definition)},
        )

        content = response.json()
        phrases = content.get("combinedPhrases", [])
        text = "\n".join(phrase.get("text", "") for phrase in phrases).strip()
        duration = int(content.get("durationMilliseconds", 0))
        if not text:
            raise SpeechError("Speech transcription result contains no recognized text")
        return text, duration