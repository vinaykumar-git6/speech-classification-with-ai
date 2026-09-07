from __future__ import annotations

import hashlib
import logging

import azure.durable_functions as df
import azure.functions as func

from audio_pipeline.config import Settings
from audio_pipeline.schemas import RecordingMessage, ResultDocument, TranscriptDocument
from audio_pipeline.services import PipelineServices

app = df.DFApp(http_auth_level=func.AuthLevel.FUNCTION)


def _services() -> PipelineServices:
    return PipelineServices(Settings.from_env())


@app.blob_trigger(
    arg_name="blob",
    path="%INPUT_CONTAINER%/{name}",
    connection="STORAGE_CONNECTION",
    source=func.BlobSource.EVENT_GRID,
)
@app.durable_client_input(client_name="client")
async def recording_uploaded(
    blob: func.InputStream, client: df.DurableOrchestrationClient
) -> None:
    settings = Settings.from_env()
    etag = str(blob.properties.get("etag", ""))
    recording_id = hashlib.sha256(f"{blob.name}:{etag}".encode()).hexdigest()[:32]
    message = RecordingMessage(
        recording_id=recording_id,
        container=settings.input_container,
        blob_name=blob.name.removeprefix(f"{settings.input_container}/"),
        etag=etag,
        locale=settings.default_locale,
    )
    instance_id = f"audio-{recording_id}"
    status = await client.get_status(instance_id)
    if status is None or status.runtime_status in {
        df.OrchestrationRuntimeStatus.COMPLETED,
        df.OrchestrationRuntimeStatus.FAILED,
        df.OrchestrationRuntimeStatus.TERMINATED,
    }:
        await client.start_new("audio_orchestrator", instance_id, message.model_dump())
        logging.info("Started orchestration %s for %s", instance_id, blob.name)


@app.orchestration_trigger(context_name="context")
def audio_orchestrator(context: df.DurableOrchestrationContext):
    recording = context.get_input()
    if (yield context.call_activity("result_exists", recording)):
        return {"status": "already_processed", "recording_id": recording["recording_id"]}

    transcript = yield context.call_activity("transcribe_recording", recording)
    classification = yield context.call_activity("classify_transcript", transcript)
    result_url = yield context.call_activity(
        "store_result",
        {"recording": recording, "transcript": transcript, "classification": classification},
    )
    return {
        "status": "completed",
        "recording_id": recording["recording_id"],
        "result_url": result_url,
    }


@app.activity_trigger(input_name="payload")
def result_exists(payload: dict) -> bool:
    return _services().result_exists(RecordingMessage.model_validate(payload))


@app.activity_trigger(input_name="payload")
def transcribe_recording(payload: dict) -> dict:
    recording = RecordingMessage.model_validate(payload)
    return _services().transcribe(recording).model_dump()


@app.activity_trigger(input_name="payload")
def classify_transcript(payload: dict) -> dict:
    return _services().classify(TranscriptDocument.model_validate(payload)).model_dump()


@app.activity_trigger(input_name="payload")
def store_result(payload: dict) -> str:
    return _services().save_result(ResultDocument.model_validate(payload))