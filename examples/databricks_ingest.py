from pyspark.sql import functions as F
from pyspark.sql import types as T

storage_account = "<storage-account-name>"
source = f"abfss://results@{storage_account}.dfs.core.windows.net/classified/*.json"

schema = T.StructType(
    [
        T.StructField("schema_version", T.StringType(), False),
        T.StructField(
            "recording",
            T.StructType(
                [
                    T.StructField("recording_id", T.StringType(), False),
                    T.StructField("container", T.StringType(), False),
                    T.StructField("blob_name", T.StringType(), False),
                    T.StructField("etag", T.StringType(), False),
                    T.StructField("locale", T.StringType(), False),
                ]
            ),
            False,
        ),
        T.StructField(
            "transcript",
            T.StructType(
                [
                    T.StructField("recording_id", T.StringType(), False),
                    T.StructField("source_etag", T.StringType(), False),
                    T.StructField("locale", T.StringType(), False),
                    T.StructField("text", T.StringType(), False),
                    T.StructField("duration_milliseconds", T.LongType(), False),
                ]
            ),
            False,
        ),
        T.StructField(
            "classification",
            T.StructType(
                [
                    T.StructField("category", T.StringType(), False),
                    T.StructField("confidence", T.DoubleType(), False),
                    T.StructField("summary", T.StringType(), False),
                    T.StructField("rationale", T.StringType(), False),
                    T.StructField("requires_human_review", T.BooleanType(), False),
                ]
            ),
            False,
        ),
        T.StructField("processed_at", T.TimestampType(), False),
    ]
)

updates = (
    spark.read.schema(schema)
    .option("multiLine", True)
    .json(source)
    .withColumn("ingested_at", F.current_timestamp())
)

updates.createOrReplaceTempView("audio_classification_updates")

spark.sql(
    """
    MERGE INTO audio_intelligence.classifications AS target
    USING audio_classification_updates AS source
    ON target.recording.recording_id = source.recording.recording_id
    WHEN MATCHED AND target.recording.etag <> source.recording.etag THEN UPDATE SET *
    WHEN NOT MATCHED THEN INSERT *
    """
)