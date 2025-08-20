from django.contrib.gis.db import models
from django.core.exceptions import ValidationError
from django.utils import timezone
import uuid
from accounts.models import Chauffeur
from geofence.models import BufferZone, PickupZone


class TaxiQueue(models.Model):
    """
    Represents a queue for a specific BufferZone-PickupZone pair.
    Manages the flow of taxis from buffer zone(s) to pickup zone(s).
    """

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    buffer_zone = models.ForeignKey(
        BufferZone,
        on_delete=models.CASCADE,
    )
    pickup_zone = models.ForeignKey(PickupZone, on_delete=models.CASCADE)
    name = models.CharField(max_length=200, blank=True)
    notification_timeout_minutes = models.PositiveIntegerField(default=2)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    active = models.BooleanField(default=True)

    class Meta:
        unique_together = ("buffer_zone", "pickup_zone")
        indexes = [
            models.Index(fields=["buffer_zone", "pickup_zone"]),
            models.Index(fields=["active"]),
        ]

    def save(self, *args, **kwargs):
        if not self.name:
            self.name = f"{self.buffer_zone.name} --> {self.pickup_zone.name}"
        super().save(*args, **kwargs)

    def get_waiting_entries(self):
        print("RUNNING GET_WAITING_ENTRIES")
        """Get all queue entries that are waiting, ordered by sign-up time."""
        return self.queueentry_set.filter(status=QueueEntry.Status.WAITING).order_by(
            "created_at"
        )

    def get_next_in_queue(self, count=1):
        print("RUNNING GET_NEXT_IN_QUEUE")
        """Get the next N chauffeurs in queue."""
        return self.get_waiting_entries()[:count]

    def get_recently_dequeued(self, limit=7):
        print("RUNNING GET_RECENTLY_DEQUEUED")
        """Get the most recently dequeued entries (for officer visibility)."""
        return self.queueentry_set.filter(status=QueueEntry.Status.DEQUEUED).order_by(
            "-dequeued_at"
        )[:limit]

    def get_queue_position(self, chauffeur):
        print("RUNNING GET_QUEUE_POSITION")
        """Get the position of a chauffeur in the queue (1-indexed)."""
        try:
            entry = self.queueentry_set.get(
                chauffeur=chauffeur, status=QueueEntry.Status.WAITING
            )
            waiting_entries = list(self.get_waiting_entries())
            return waiting_entries.index(entry) + 1
        except (QueueEntry.DoesNotExist, ValueError):
            return None

    def has_available_slots(self, count=1):
        """Check if pickup zone has available slots for the specified number of taxis."""
        return self.pickup_zone.get_available_slots() >= count

    def __str__(self):
        return self.name or f"Queue {self.uuid}"


class QueueEntry(models.Model):
    """
    Represents a chauffeur's entry in a specific taxi queue.
    Tracks their status throughout the queuing process.
    """

    class Status(models.TextChoices):
        WAITING = "waiting", "Waiting in Queue"
        NOTIFIED = "notified", "Notified to Leave"
        DEQUEUED = "dequeued", "Dequeued (Allowed to Pickup)"
        DECLINED = "declined", "Declined Notification"
        TIMEOUT = "timeout", "Notification Timeout"
        LEFT_ZONE = "left_zone", "Left Buffer Zone"

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    queue = models.ForeignKey(TaxiQueue, on_delete=models.CASCADE)
    chauffeur = models.ForeignKey(Chauffeur, on_delete=models.CASCADE)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.WAITING
    )

    created_at = models.DateTimeField(auto_now_add=True)
    notified_at = models.DateTimeField(null=True, blank=True)
    dequeued_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Location tracking
    signup_location = models.PointField(null=True, blank=True, srid=4326)

    class Meta:
        unique_together = ("queue", "chauffeur")
        indexes = [
            models.Index(fields=["queue", "status"]),
            models.Index(fields=["chauffeur", "status"]),
            models.Index(fields=["status", "created_at"]),
            models.Index(fields=["status", "notified_at"]),
        ]

    def clean(self):
        """Validate that chauffeur is not in another active queue."""
        if self.pk is None:
            active_entries = QueueEntry.objects.filter(
                chauffeur=self.chauffeur,
                status__in=[self.Status.WAITING, self.Status.NOTIFIED],
            ).exclude(pk=self.pk if self.pk else None)

            if active_entries.exists():
                raise ValidationError(
                    f"Chauffeur {self.chauffeur} is already in another queue."
                )

    def save(self, *args, **kwargs):
        self.full_clean()  # Full clean to be sure
        super().save(*args, **kwargs)

    def notify(self):
        """Mark entry as notified and create notification record."""
        if self.status != self.Status.WAITING:
            raise ValidationError(f"Cannot notify chauffeur with status: {self.status}")

        self.status = self.Status.NOTIFIED
        self.notified_at = timezone.now()
        self.save()

        # Create notification record
        notification = QueueNotification.objects.create(
            queue_entry=self, notification_time=self.notified_at
        )
        return notification

    def dequeue(self):
        """Mark entry as dequeued (allowed to go to pickup zone)."""
        if self.status != self.Status.NOTIFIED:
            raise ValidationError(
                f"Cannot dequeue chauffeur with status: {self.status}"
            )

        self.status = self.Status.DEQUEUED
        self.dequeued_at = timezone.now()
        self.save()

    def decline_notification(self):
        """Mark that chauffeur declined the notification."""
        if self.status != self.Status.NOTIFIED:
            raise ValidationError(
                f"Cannot decline notification with status: {self.status}"
            )

        self.status = self.Status.DECLINED
        self.save()

    def timeout_notification(self):
        """Mark that notification timed out."""
        if self.status != self.Status.NOTIFIED:
            raise ValidationError(
                f"Cannot timeout notification with status: {self.status}"
            )

        self.status = self.Status.TIMEOUT
        self.save()

    def is_notification_expired(self):
        """Check if notification has expired based on timeout setting."""
        if self.status != self.Status.NOTIFIED or not self.notified_at:
            return False

        timeout_minutes = self.queue.notification_timeout_minutes
        expiry_time = self.notified_at + timezone.timedelta(minutes=timeout_minutes)
        return timezone.now() > expiry_time

    def get_queue_position(self):
        """Get current position in queue (1-indexed)."""
        return self.queue.get_queue_position(self.chauffeur)

    def __str__(self):
        return f"{self.chauffeur} in {self.queue.name} ({self.get_status_display()})"


class QueueNotification(models.Model):
    """
    Tracks notifications sent to chauffeurs and their responses.
    Used for history, analytics, and timeout management.
    """

    class ResponseType(models.TextChoices):
        PENDING = "pending", "Pending Response"
        ACCEPTED = "accepted", "Accepted (Will Leave)"
        DECLINED = "declined", "Declined (Will Stay)"
        TIMEOUT = "timeout", "No Response (Timeout)"

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    queue_entry = models.ForeignKey(QueueEntry, on_delete=models.CASCADE)
    notification_time = models.DateTimeField(default=timezone.now)
    response_time = models.DateTimeField(null=True, blank=True)
    response = models.CharField(
        max_length=20, choices=ResponseType.choices, default=ResponseType.PENDING
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["queue_entry", "notification_time"]),
            models.Index(fields=["response", "notification_time"]),
            models.Index(fields=["notification_time"]),
        ]

    def respond(self, response_type):
        """Record chauffeur's response to notification."""
        if self.response != self.ResponseType.PENDING:
            raise ValidationError("Notification has already been responded to.")

        self.response = response_type
        self.response_time = timezone.now()
        self.save()

        # Update queue entry status
        if response_type == self.ResponseType.ACCEPTED:
            self.queue_entry.dequeue()
        elif response_type == self.ResponseType.DECLINED:
            self.queue_entry.decline_notification()
        elif response_type == self.ResponseType.TIMEOUT:
            self.queue_entry.timeout_notification()

    def is_expired(self):
        """Check if notification has expired."""
        return self.queue_entry.is_notification_expired()

    def __str__(self):
        return f"Notification to {self.queue_entry.chauffeur} at {self.notification_time} ({self.get_response_display()})"


class QueueManager(models.Manager):
    """Custom manager for queue-related operations."""

    def get_or_create_queue(self, buffer_zone, pickup_zone):
        """Get or create a queue for the given zone pair."""
        return self.get_or_create(
            buffer_zone=buffer_zone, pickup_zone=pickup_zone, defaults={"active": True}
        )

    def active_queues(self):
        """Get all active queues."""
        return self.filter(active=True)


TaxiQueue.add_to_class("objects", QueueManager())
