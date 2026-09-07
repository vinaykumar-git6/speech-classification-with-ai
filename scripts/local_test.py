"""Transcribe and classify audio files from a local folder.

Reads and writes local folders instead of Blob Storage, and skips Event Grid and
Durable Functions, so the Foundry Speech and model endpoints can be validated on
their own. Configuration comes from .env.

    python scripts/local_test.py
    python scripts/local_test.py samples/recordings/call-0001-complaint.wav
    python scripts/local_test.py --workers 12 --force
"""

from __future__ import annotations

import argparse
import os
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

# Run straight from a clone, without requiring `pip install -e .`.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from audio_pipeline.config import Settings  # noqa: E402
from audio_pipeline.schemas import (  # noqa: E402
    RecordingMessage,
    ResultDocument,
    TranscriptDocument,
)
from audio_pipeline.services import PipelineServices  # noqa: E402

AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".webm"}


def collect(target: Path) -> list[Path]:
    if target.is_file():
        return [target]
    if target.is_dir():
        return sorted(p for p in target.iterdir() if p.suffix.lower() in AUDIO_SUFFIXES)
    raise SystemExit(f"No such file or folder: {target}")


@dataclass
class Outcome:
    path: Path
    result: ResultDocument | None = None
    error: str | None = None
    transcribe_seconds: float = 0.0
    classify_seconds: float = 0.0

    @property
    def service_seconds(self) -> float:
        return self.transcribe_seconds + self.classify_seconds

    def line(self) -> str:
        if self.result is None:
            return f"{self.path.name}  FAILED  {self.error}"
        classification = self.result.classification
        return (
            f"{self.path.name}  {classification.category} "
            f"({classification.confidence:.2f})  "
            f"transcribe {self.transcribe_seconds:.1f}s  "
            f"classify {self.classify_seconds:.1f}s"
        )


def run_one(
    services: PipelineServices, path: Path, locale: str
) -> tuple[ResultDocument, float, float]:
    audio = path.read_bytes()
    started = time.perf_counter()
    text, duration_milliseconds = services.speech.transcribe(audio, path.name, locale)
    transcribed = time.perf_counter()
    transcript = TranscriptDocument(
        recording_id=path.stem,
        source_etag="local",
        locale=locale,
        text=text,
        duration_milliseconds=duration_milliseconds,
    )
    result = ResultDocument(
        recording=RecordingMessage(
            recording_id=path.stem,
            container=str(path.parent),
            blob_name=path.name,
            etag="local",
            locale=locale,
        ),
        transcript=transcript,
        classification=services.classify(transcript),
    )
    return result, transcribed - started, time.perf_counter() - transcribed


def process(
    services: PipelineServices, path: Path, locale: str, output_dir: Path
) -> Outcome:
    try:
        result, transcribe_seconds, classify_seconds = run_one(services, path, locale)
    except Exception as error:  # one bad recording must not end the batch
        return Outcome(path, error=f"{type(error).__name__}: {error}")
    destination = output_dir / f"{path.stem}.json"
    destination.write_text(result.model_dump_json(indent=2), encoding="utf-8")
    return Outcome(path, result, None, transcribe_seconds, classify_seconds)


def report(outcomes: list[Outcome], wall_seconds: float, workers: int) -> None:
    done = [item for item in outcomes if item.result is not None]
    failed = [item for item in outcomes if item.result is None]

    print("\n" + "-" * 68)
    print(f"processed         {len(done)} ok, {len(failed)} failed, {workers} worker(s)")
    print(f"wall clock        {wall_seconds:.1f}s")
    if done:
        audio_seconds = sum(i.result.transcript.duration_milliseconds for i in done) / 1000
        transcribe_seconds = sum(i.transcribe_seconds for i in done)
        classify_seconds = sum(i.classify_seconds for i in done)
        service_seconds = transcribe_seconds + classify_seconds
        print(f"audio processed   {audio_seconds / 60:.1f} min")
        print(f"service time      {service_seconds:.1f}s summed across threads")
        print(f"speedup           {service_seconds / wall_seconds:.1f}x versus serial")
        print(
            f"per recording     {wall_seconds / len(done):.1f}s wall, "
            f"{service_seconds / len(done):.1f}s service"
        )
        print(f"realtime factor   {audio_seconds / wall_seconds:.1f}x audio per second")
        print(
            f"split             transcribe {transcribe_seconds / service_seconds:.0%}, "
            f"classify {classify_seconds / service_seconds:.0%}"
        )
        categories = Counter(i.result.classification.category for i in done)
        print(
            "categories        "
            + ", ".join(f"{name} {count}" for name, count in sorted(categories.items()))
        )
        review = sum(1 for i in done if i.result.classification.requires_human_review)
        print(f"human review      {review}")
    for item in failed:
        print(f"FAILED {item.path.name}: {item.error}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run local recordings through the pipeline.")
    parser.add_argument("target", nargs="?", help="Audio file or folder (default LOCAL_INPUT_DIR)")
    parser.add_argument("--output", help="Folder for result JSON (default LOCAL_OUTPUT_DIR)")
    parser.add_argument("--locale", help="Override DEFAULT_LOCALE, for example en-US")
    parser.add_argument("--limit", type=int, help="Stop after this many files")
    parser.add_argument("--force", action="store_true", help="Re-run files that have results")
    parser.add_argument(
        "--workers", type=int, default=8, help="Recordings to process concurrently (default 8)"
    )
    parser.add_argument("--env-file", type=Path, default=Path(".env"), help="Path to the .env file")
    args = parser.parse_args()

    load_dotenv(args.env_file)

    target = Path(args.target or os.getenv("LOCAL_INPUT_DIR", "samples/recordings"))
    output_dir = Path(args.output or os.getenv("LOCAL_OUTPUT_DIR", "samples/results"))
    files = collect(target)[: args.limit]
    if not files:
        raise SystemExit(f"No audio files found in {target}")

    settings = Settings.from_env()
    services = PipelineServices(settings)
    locale = args.locale or settings.default_locale
    output_dir.mkdir(parents=True, exist_ok=True)

    pending = [p for p in files if args.force or not (output_dir / f"{p.stem}.json").exists()]
    if len(pending) < len(files):
        print(f"{len(files) - len(pending)} file(s) skipped, results already exist")
    if not pending:
        return 0

    workers = max(1, min(args.workers, len(pending)))
    print(f"{len(pending)} file(s) from {target} -> {output_dir} on {workers} worker(s)\n")

    # Warm the token cache so worker threads do not each spawn an Azure CLI probe.
    services.credential.get_token("https://cognitiveservices.azure.com/.default")
    services.credential.get_token("https://ai.azure.com/.default")

    lock = threading.Lock()
    outcomes: list[Outcome] = []
    started = time.perf_counter()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(process, services, path, locale, output_dir) for path in pending]
        for future in as_completed(futures):
            outcome = future.result()
            with lock:
                outcomes.append(outcome)
                print(f"[{len(outcomes):>3}/{len(pending)}] {outcome.line()}", flush=True)
    wall_seconds = time.perf_counter() - started

    report(outcomes, wall_seconds, workers)
    return 1 if any(item.result is None for item in outcomes) else 0


if __name__ == "__main__":
    raise SystemExit(main())
