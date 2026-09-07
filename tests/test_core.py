import asyncio

from audio_pipeline.core import Classification, Pipeline, Recording, Transcript


class FakeTranscriber:
    calls = 0

    async def transcribe(self, recording: Recording) -> Transcript:
        self.calls += 1
        return Transcript(recording.recording_id, "cancel my order", recording.etag)


class FakeClassifier:
    calls = 0

    async def classify(self, transcript: Transcript) -> Classification:
        self.calls += 1
        return Classification(transcript.recording_id, "cancellation", 0.98, "Cancel")


class MemoryStore:
    def __init__(self) -> None:
        self.items: dict[str, tuple[Transcript, Classification]] = {}

    async def exists(self, recording_id: str, source_etag: str) -> bool:
        item = self.items.get(recording_id)
        return item is not None and item[0].source_etag == source_etag

    async def save(
        self, transcript: Transcript, classification: Classification
    ) -> None:
        self.items[transcript.recording_id] = (transcript, classification)


def test_duplicate_delivery_is_idempotent() -> None:
    transcriber = FakeTranscriber()
    classifier = FakeClassifier()
    store = MemoryStore()
    pipeline = Pipeline(transcriber, classifier, store)
    recording = Recording("call-1", "https://example/audio.wav", '"etag-1"')

    assert asyncio.run(pipeline.process(recording)) is True
    assert asyncio.run(pipeline.process(recording)) is False
    assert transcriber.calls == 1
    assert classifier.calls == 1
    assert len(store.items) == 1