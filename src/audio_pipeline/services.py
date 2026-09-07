from __future__ import annotations

import os

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.storage.blob import BlobServiceClient, ContentSettings
from openai import OpenAI

from audio_pipeline.config import Settings
from audio_pipeline.schemas import (
    ClassificationDocument,
    RecordingMessage,
    ResultDocument,
    TranscriptDocument,
)
from audio_pipeline.speech import SpeechClient


class PipelineServices:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.credential = DefaultAzureCredential()
        self._blobs: BlobServiceClient | None = None
        self.speech = SpeechClient(
            settings.speech_endpoint,
            settings.speech_api_version,
            self.credential,
            os.getenv("SPEECH_API_KEY"),
            settings.speech_timeout_seconds,
        )
        token_provider = get_bearer_token_provider(
            self.credential, "https://ai.azure.com/.default"
        )
        self.openai = OpenAI(
            base_url=f"{settings.openai_endpoint.rstrip('/')}/", api_key=token_provider
        )

    @property
    def blobs(self) -> BlobServiceClient:
        if self._blobs is None:
            if not self.settings.storage_account_url:
                raise ValueError(
                    "STORAGE_ACCOUNT_URL is required for Blob Storage operations"
                )
            self._blobs = BlobServiceClient(self.settings.storage_account_url, self.credential)
        return self._blobs

    def result_blob_name(self, recording_id: str) -> str:
        return f"classified/{recording_id}.json"

    def result_exists(self, recording: RecordingMessage) -> bool:
        client = self.blobs.get_blob_client(
            self.settings.output_container, self.result_blob_name(recording.recording_id)
        )
        if not client.exists():
            return False
        metadata = client.get_blob_properties().metadata
        return metadata.get("source_etag") == recording.etag.strip('"')

    def download_audio(self, recording: RecordingMessage) -> bytes:
        blob = self.blobs.get_blob_client(recording.container, recording.blob_name)
        return blob.download_blob().readall()

    def transcribe(self, recording: RecordingMessage) -> TranscriptDocument:
        audio = self.download_audio(recording)
        text, duration = self.speech.transcribe(
            audio, recording.blob_name.rsplit("/", 1)[-1], recording.locale
        )
        return TranscriptDocument(
            recording_id=recording.recording_id,
            source_etag=recording.etag,
            locale=recording.locale,
            text=text,
            duration_milliseconds=duration,
        )

    def classify(self, transcript: TranscriptDocument) -> ClassificationDocument:
        categories = ", ".join(self.settings.categories)
        completion = self.openai.beta.chat.completions.parse(
            model=self.settings.openai_deployment,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "Classify contact-center transcripts. Use exactly one allowed category. "
                        "Set requires_human_review when confidence is below 0.75, the content is "
                        "ambiguous, or a safety/compliance decision is involved. "
                        "Do not invent facts."
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"Allowed categories: {categories}\n\nTranscript:\n{transcript.text}"
                    ),
                },
            ],
            response_format=ClassificationDocument,
        )
        message = completion.choices[0].message
        if message.refusal:
            raise RuntimeError(
                f"Classification request refused: {message.refusal}"
            )
        if message.parsed is None:
            raise RuntimeError("Classification response did not match the required schema")
        if message.parsed.category not in self.settings.categories:
            raise RuntimeError(
                f"Model returned disallowed category: {message.parsed.category}"
            )
        return message.parsed

    def save_result(self, result: ResultDocument) -> str:
        blob = self.blobs.get_blob_client(
            self.settings.output_container, self.result_blob_name(result.recording.recording_id)
        )
        blob.upload_blob(
            result.model_dump_json(indent=2),
            overwrite=True,
            metadata={"source_etag": result.recording.etag.strip('"')},
            content_settings=ContentSettings(content_type="application/json"),
        )
        return blob.url