from __future__ import annotations

from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict, Field


class RecordingMessage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    recording_id: str
    container: str
    blob_name: str
    etag: str
    locale: str = "en-US"


class TranscriptDocument(BaseModel):
    model_config = ConfigDict(extra="forbid")

    recording_id: str
    source_etag: str
    locale: str
    text: str
    duration_milliseconds: int = 0


class ClassificationDocument(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: str
    confidence: float = Field(ge=0, le=1)
    summary: str
    rationale: str
    requires_human_review: bool


class ResultDocument(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str = "1.0"
    recording: RecordingMessage
    transcript: TranscriptDocument
    classification: ClassificationDocument
    processed_at: datetime = Field(default_factory=lambda: datetime.now(UTC))