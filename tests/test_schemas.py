import pytest
from pydantic import ValidationError

from audio_pipeline.schemas import (
    ClassificationDocument,
    RecordingMessage,
    ResultDocument,
    TranscriptDocument,
)


def test_result_document_is_delta_friendly_and_strict() -> None:
    result = ResultDocument(
        recording=RecordingMessage(
            recording_id="abc", container="recordings", blob_name="2026/call.wav", etag="v1"
        ),
        transcript=TranscriptDocument(
            recording_id="abc", source_etag="v1", locale="en-US", text="Please cancel."
        ),
        classification=ClassificationDocument(
            category="cancellation",
            confidence=0.97,
            summary="Customer requests cancellation.",
            rationale="Explicit cancellation request.",
            requires_human_review=False,
        ),
    )

    document = result.model_dump(mode="json")
    assert document["schema_version"] == "1.0"
    assert document["recording"]["blob_name"] == "2026/call.wav"
    assert document["classification"]["confidence"] == 0.97


def test_confidence_must_be_normalized() -> None:
    with pytest.raises(ValidationError):
        ClassificationDocument(
            category="other",
            confidence=98,
            summary="Summary",
            rationale="Reason",
            requires_human_review=False,
        )


def test_recording_message_rejects_unknown_fields() -> None:
    with pytest.raises(ValidationError):
        RecordingMessage(
            recording_id="abc",
            container="recordings",
            blob_name="call.wav",
            etag="v1",
            poll_interval_seconds=20,
        )