from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Recording:
    recording_id: str
    blob_url: str
    etag: str
    locale: str = "en-US"


@dataclass(frozen=True)
class Transcript:
    recording_id: str
    text: str
    source_etag: str


@dataclass(frozen=True)
class Classification:
    recording_id: str
    category: str
    confidence: float
    summary: str


class Transcriber(Protocol):
    async def transcribe(self, recording: Recording) -> Transcript: ...


class Classifier(Protocol):
    async def classify(self, transcript: Transcript) -> Classification: ...


class ResultStore(Protocol):
    async def exists(self, recording_id: str, source_etag: str) -> bool: ...

    async def save(
        self, transcript: Transcript, classification: Classification
    ) -> None: ...


class Pipeline:
    def __init__(
        self,
        transcriber: Transcriber,
        classifier: Classifier,
        result_store: ResultStore,
    ) -> None:
        self._transcriber = transcriber
        self._classifier = classifier
        self._result_store = result_store

    async def process(self, recording: Recording) -> bool:
        """Process one recording, returning False when it was already completed."""
        if await self._result_store.exists(recording.recording_id, recording.etag):
            return False

        transcript = await self._transcriber.transcribe(recording)
        classification = await self._classifier.classify(transcript)
        await self._result_store.save(transcript, classification)
        return True
