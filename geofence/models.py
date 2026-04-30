from django.contrib.gis.db import models
import uuid
from channels.db import database_sync_to_async
from django.db.models import Subquery, OuterRef
from .services import point_in_buffer

# Create your models here.

class BufferZone(models.Model):
    """Represents a geographical buffer zone."""
    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    name = models.CharField(max_length=100, unique=True, null=True, blank=True)
    zone = models.PolygonField(srid=4326, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    active = models.BooleanField(default=True)

    def contains_lat_lang(self, latitude: float, longitude: float, inclusive: bool = True) -> bool:
        """Conveniece wrapper: returns True if (latitude, longitude) is inside the buffer zone."""
        return point_in_buffer(self, latitude, longitude, inclusive=inclusive)


class PickupZone(models.Model):
    """Represents a geographical pickup zone."""
    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    name = models.CharField(max_length=100, unique=True, null=True, blank=True)
    address = models.CharField(max_length=255, null=True, blank=True)
    image_url = models.CharField(max_length=500, null=True, blank=True)
    total_sensors = models.PositiveIntegerField(default=0)
    num_of_occupied_sensors = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    active = models.BooleanField(default=True)

    @property
    def image(self):
        """Allow templates to query pickup_zone.image for backward compatibility."""
        return self.image_url

    def get_available_slots(self) -> int:
        """Get the number of total slots in the pickup zone."""
        return self.total_sensors
    
    @database_sync_to_async
    def get_occupied_sensors(self):
        from sensors.models import SensorReading
        # Subquery to get the latest SensorReading for each sensor
        subquery = SensorReading.objects.filter(sensor__active=True,
                                             sensor=OuterRef('sensor')
                                             ).order_by('-id').values('id')[:1]

        # Get the latest sensor data for each sensor in the pickup zone and filter before slicing
        latest_sensor_data = SensorReading.objects.filter(
            id__in=Subquery(subquery),
            sensor__pickup_zone=self  # Filter by pickup zone
        ).order_by('-id')  # Apply status filter before slicing
        # Slice the query only after filtering is complete
        count = sum(1 for data in latest_sensor_data if data.status is True)
        return count
