from __future__ import annotations

import os
from dataclasses import dataclass


def _required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Required environment variable {name} is missing")
    return value.rstrip("/")


def _optional(name: str) -> str:
    return (os.getenv(name) or "").rstrip("/")


@dataclass(frozen=True)
class Settings:
    # Empty when running locally against folders instead of Blob Storage.
    storage_account_url: str
    input_container: str
    output_container: str
    speech_endpoint: str
    speech_api_version: str
    openai_endpoint: str
    openai_deployment: str
    categories: tuple[str, ...]
    default_locale: str
    speech_timeout_seconds: int

    @classmethod
    def from_env(cls) -> Settings:
        categories = tuple(
            item.strip()
            for item in os.getenv(
                "CLASSIFICATION_CATEGORIES",
                "complaint,cancellation,sales,service_request,fraud,other",
            ).split(",")
            if item.strip()
        )
        if not categories:
            raise ValueError("CLASSIFICATION_CATEGORIES must contain at least one category")

        return cls(
            storage_account_url=_optional("STORAGE_ACCOUNT_URL"),
            input_container=os.getenv("INPUT_CONTAINER", "recordings"),
            output_container=os.getenv("OUTPUT_CONTAINER", "results"),
            speech_endpoint=_required("SPEECH_ENDPOINT"),
            speech_api_version=os.getenv("SPEECH_API_VERSION", "2025-10-15"),
            openai_endpoint=_required("AZURE_OPENAI_ENDPOINT"),
            openai_deployment=os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-5-mini"),
            categories=categories,
            default_locale=os.getenv("DEFAULT_LOCALE", "en-US"),
            speech_timeout_seconds=int(os.getenv("SPEECH_TIMEOUT_SECONDS", "600")),
        )