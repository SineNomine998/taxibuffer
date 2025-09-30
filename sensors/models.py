import uuid
from django.db import models
from geofence.models import PickupZone


class Sensor(models.Model):
    """Represents a sensor in a pickup zone."""

    id = models.BigAutoField(primary_key=True)
    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    sensor_id = models.CharField(blank=False, max_length=255)
    pickup_zone = models.ForeignKey(
        PickupZone, related_name="sensors", on_delete=models.CASCADE
    )
    created_at = models.DateTimeField(auto_now_add=True)
    modified_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    deleted = models.BooleanField(default=False)
    active = models.BooleanField(default=True)

    def __str__(self):
        return f"Sensor {self.sensor_id} at {self.pickup_zone.name}"

    class Meta:
        indexes = [
            models.Index(fields=["sensor_id"]),
            models.Index(fields=["pickup_zone", "active"]),
        ]


class SensorReading(models.Model):
    """Represents a reading from a sensor in a pickup zone."""

    id = models.BigAutoField(primary_key=True)
    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    sensor = models.ForeignKey(Sensor, on_delete=models.CASCADE)
    date = models.DateTimeField(blank=False)
    status = models.BooleanField()
    modified_at = models.DateTimeField(null=True, blank=True)
    deleted = models.BooleanField(default=False)

    def __str__(self):
        status = "Occupied" if self.status else "Free"
        return f"{self.sensor.sensor_id} at {self.date}: {status}"

    class Meta:
        indexes = [
            models.Index(fields=["sensor", "date"]),
            models.Index(fields=["status"], name="status_idx"),
        ]


class ApiKey(models.Model):
    """API keys for accessing sensor data. (copied from CTC project hehe :sweat_smile:)"""
    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    key = models.TextField(null=False)
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(blank=True, null=True)
    label = models.CharField(max_length=255)
    description = models.TextField()
