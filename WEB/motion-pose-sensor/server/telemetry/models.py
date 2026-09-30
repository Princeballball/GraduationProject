from django.db import models


class Device(models.Model):
    device_id = models.UUIDField(primary_key=True)
    device_kind = models.CharField(max_length=6)
    last_seen_at = models.DateTimeField()
    last_timestamp_ms = models.BigIntegerField()


class TelemetrySample(models.Model):
    device = models.ForeignKey(Device, on_delete=models.CASCADE, related_name="samples")
    type = models.CharField(max_length=9)
    timestamp_ms = models.BigIntegerField()
    motion = models.JSONField(null=True, blank=True)
    body_pose = models.JSONField(null=True, blank=True)
    received_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["device", "timestamp_ms"], name="sample_device_time_idx"),
            models.Index(fields=["device", "type", "timestamp_ms"], name="sample_device_type_time_idx"),
        ]
