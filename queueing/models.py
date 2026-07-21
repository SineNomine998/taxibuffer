from django.contrib.gis.db import models
from django.core.exceptions import ValidationError
from django.utils import timezone
from django.db import transaction
from django.db.models import Q
import uuid
from accounts.models import Chauffeur, VehicleType
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
    notifications_paused = models.BooleanField(
        default=False,
        help_text="If true, no new notifications will be sent for this queue.",
    )
    next_notification_number = models.PositiveIntegerField(default=1)

    class Meta:
        unique_together = ("buffer_zone", "pickup_zone")
        indexes = [
            models.Index(fields=["buffer_zone", "pickup_zone"]),
            models.Index(fields=["active"]),
        ]

    def save(self, *args, **kwargs):
        was_active = None

        if self.pk:
            was_active = (
                TaxiQueue.objects.filter(pk=self.pk)
                .values_list("active", flat=True)
                .first()
            )

        if not self.name:
            self.name = f"{self.buffer_zone.name} --> {self.pickup_zone.name}"

        super().save(*args, **kwargs)

        if was_active is True and self.active is False:
            self.close_active_entries()

    def get_waiting_entries(self):
        """Get all queue entries that are waiting, ordered by sign-up time."""
        return self.queueentry_set.filter(status=QueueEntry.Status.WAITING).order_by(
            "created_at"
        )

    def get_waiting_entries_control(self):
        """Get all queue entries that are waiting, ordered by sign-up time."""
        return self.queueentry_set.filter(status=QueueEntry.Status.WAITING).order_by(
            "-created_at"
        )

    def get_next_in_queue(self, count=1):
        """Get the next n chauffeurs in queue."""
        return self.get_waiting_entries()[:count]

    def get_recently_dequeued(self, limit=7):
        return self.queueentry_set.filter(status=QueueEntry.Status.DEQUEUED).order_by(
            "-dequeued_at"
        )[:limit]

    def get_queue_position(self, chauffeur):
        try:
            entry = self.queueentry_set.get(
                chauffeur=chauffeur, status=QueueEntry.Status.WAITING
            )
            waiting_entries = list(self.get_waiting_entries())
            return waiting_entries.index(entry) + 1
        except (QueueEntry.DoesNotExist, ValueError):
            return None

    def close_active_entries(self):
        return self.queueentry_set.filter(
            status__in=[
                QueueEntry.Status.WAITING,
                QueueEntry.Status.NOTIFIED,
            ]
        ).update(
            status=QueueEntry.Status.QUEUE_CLOSED,
            updated_at=timezone.now(),
        )

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
        # DECLINED = "declined", "Declined Notification"
        # TIMEOUT = "timeout", "Notification Timeout"
        QUEUE_CLOSED = "queue_closed", "Queue Closed"
        LEFT_ZONE = "left_zone", "Left Buffer Zone"
        LEFT_QUEUE = "left_queue", "Left Queue"
        BLOCKED = "blocked", "Blocked"

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    queue = models.ForeignKey(TaxiQueue, on_delete=models.CASCADE)
    chauffeur = models.ForeignKey(Chauffeur, on_delete=models.CASCADE)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.WAITING
    )
    vehicle = models.ForeignKey(
        "accounts.ChauffeurVehicle",
        on_delete=models.PROTECT,
        null=True,
        blank=True,
    )
    vehicle_type = models.CharField(
        max_length=10, choices=VehicleType.choices, null=True, blank=True
    )
    license_plate_snapshot = models.CharField(max_length=20, null=True, blank=True)
    normalized_license_plate_snapshot = models.CharField(
        max_length=20,
        blank=True,
        db_index=True,
    )

    created_at = models.DateTimeField(auto_now_add=True)
    notified_at = models.DateTimeField(null=True, blank=True)
    dequeued_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    signup_location = models.PointField(null=True, blank=True, srid=4326)
    location_lost_at = models.DateTimeField(null=True, blank=True)
    location_warning_sent_at = models.DateTimeField(null=True, blank=True)
    last_location_at = models.DateTimeField(null=True, blank=True)
    last_location_lat = models.FloatField(null=True, blank=True)
    last_location_lng = models.FloatField(null=True, blank=True)

    class Meta:
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
        self.full_clean()
        super().save(*args, **kwargs)

    def notify(self):
        from .activity import log_chauffeur_activity

        """Mark entry as notified and create notification record."""
        if self.status != self.Status.WAITING:
            raise ValidationError(f"Cannot notify chauffeur with status: {self.status}")

        with transaction.atomic():
            queue = TaxiQueue.objects.select_for_update().get(pk=self.queue.pk)

            sequence = queue.next_notification_number
            queue.next_notification_number = sequence + 1
            queue.save(update_fields=["next_notification_number"])

            notification = QueueNotification.objects.create(
                queue_entry=self,
                notification_time=timezone.now(),
                response=QueueNotification.ResponseType.PENDING,
                sequence_number=sequence,
            )

            log_chauffeur_activity(
                chauffeur=self.chauffeur,
                queue=self.queue,
                queue_entry=self,
                event_type=ChauffeurActivityLog.EventType.NOTIFIED,
                title="U bent opgeroepen",
                message="Rij door naar de ophaallocatie.",
                queue_position=self.get_queue_position(),
                sequence_number=notification.sequence_number,
            )

            self.status = QueueEntry.Status.NOTIFIED
            self.notified_at = timezone.now()
            self.save(update_fields=["status", "notified_at"])

            from mobile_api.push import send_queue_called_push

            transaction.on_commit(
                lambda notification_id=notification.id: send_queue_called_push(
                    notification_id
                )
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

    # TODO! Remove timeout functionality
    # def timeout_notification(self):
    #     """Mark that notification timed out but keep them in the queue."""
    #     if self.status != self.Status.NOTIFIED:
    #         raise ValidationError(
    #             f"Cannot timeout notification with status: {self.status}"
    #         )

    #     # Change status back to WAITING instead of TIMEOUT to keep the chauffeur in queue
    #     self.status = self.Status.WAITING
    #     self.save()

    def is_notification_expired(self):
        """Check if notification has expired based on timeout setting."""
        # if self.status != self.Status.NOTIFIED or not self.notified_at:
        # return False

        # timeout_minutes = self.queue.notification_timeout_minutes
        # expiry_time = self.notified_at + timezone.timedelta(minutes=timeout_minutes)
        # return timezone.now() > expiry_time
        return False

    def get_queue_position(self):
        """Get current position in queue (1-indexed)."""
        return self.queue.get_queue_position(self.chauffeur)

    @property
    def display_license_plate(self):
        return self.license_plate_snapshot or "unknown license plate in the queue entry"

    def get_status_display(self):
        """Get a human-readable status display."""
        return self.status

    def __str__(self):
        return f"{self.chauffeur} in {self.queue.name} ({self.get_status_display()})"


class QueueNotification(models.Model):
    """
    Tracks notifications sent to chauffeurs and their responses.
    Can be used for history, analytics, and timeout management.
    """

    class ResponseType(models.TextChoices):
        PENDING = "pending", "Pending Response"
        ACCEPTED = "accepted", "Accepted (Will Leave)"
        # DECLINED = "declined", "Declined (Will Stay)"
        # TIMEOUT = "timeout", "No Response (Timeout)"

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    queue_entry = models.ForeignKey(QueueEntry, on_delete=models.CASCADE)
    notification_time = models.DateTimeField(default=timezone.now)
    response_time = models.DateTimeField(null=True, blank=True)
    response = models.CharField(
        max_length=20, choices=ResponseType.choices, default=ResponseType.PENDING
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    sequence_number = models.PositiveIntegerField(null=True, blank=True)

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)

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
        self.save(update_fields=["response", "response_time"])

        # I commented this out, because this would dequeue the chauffeur only when they accept the response
        # which doesn't make much sense in the app's flow and is not user-friendly.
        # if response_type == self.ResponseType.ACCEPTED:
        #     self.queue_entry.dequeue()
        # elif response_type == self.ResponseType.DECLINED:
        #     self.queue_entry.decline_notification()
        # elif response_type == self.ResponseType.TIMEOUT:
        #     self.queue_entry.timeout_notification()

    def is_expired(self):
        """Check if notification has expired."""
        # return self.queue_entry.is_notification_expired()
        return False

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


class PushSubscription(models.Model):
    chauffeur = models.ForeignKey(
        "accounts.Chauffeur", on_delete=models.CASCADE, null=True, blank=True
    )
    subscription_info = models.JSONField()
    entry_uuid = models.UUIDField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"PushSubscription {self.id} for chauffeur {self.chauffeur}"


class ChauffeurActivityLog(models.Model):
    class EventType(models.TextChoices):
        QUEUE_JOINED = "queue_joined", "Aangemeld"
        QUEUE_LEFT = "queue_left", "Wachtrij verlaten"
        QUEUE_POSITION_CHANGED = "queue_position_changed", "Positie gewijzigd"
        LOCATION_INSIDE = "location_inside", "Binnen bufferzone"
        LOCATION_OUTSIDE_WARNING = "location_outside_warning", "Buiten bufferzone"
        LOCATION_RECOVERED = "location_recovered", "Terug in bufferzone"
        LOCATION_UNAVAILABLE = "location_unavailable", "Locatie niet beschikbaar"
        LOCATION_TIMEOUT_DEQUEUED = (
            "location_timeout_dequeued",
            "Verwijderd door locatiecontrole",
        )
        NOTIFIED = "notified", "Opgroepen"
        NOTIFICATION_ACCEPTED = "notification_accepted", "Oproep bevestigd"
        OFFICER_DEQUEUED = "officer_dequeued", "Afgehandeld"
        SYSTEM_DEQUEUED = "system_dequeued", "Systeemverwijdering"
        BLOCKED = "blocked", "Blocked"

    chauffeur = models.ForeignKey(
        "accounts.Chauffeur",
        on_delete=models.CASCADE,
        related_name="activity_logs",
    )

    queue = models.ForeignKey(
        "queueing.TaxiQueue",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="activity_logs",
    )

    queue_entry = models.ForeignKey(
        "queueing.QueueEntry",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="activity_logs",
    )

    event_type = models.CharField(
        max_length=50,
        choices=EventType.choices,
    )

    title = models.CharField(max_length=120)
    message = models.TextField(blank=True)

    queue_position = models.PositiveIntegerField(null=True, blank=True)
    previous_queue_position = models.PositiveIntegerField(null=True, blank=True)

    sequence_number = models.PositiveIntegerField(null=True, blank=True)

    lat = models.FloatField(null=True, blank=True)
    lng = models.FloatField(null=True, blank=True)

    metadata = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["chauffeur", "-created_at"]),
            models.Index(fields=["queue_entry", "-created_at"]),
            models.Index(fields=["event_type", "-created_at"]),
        ]

    def __str__(self):
        return f"{self.chauffeur_id} - {self.event_type} - {self.created_at}"


class LicensePlateRestriction(models.Model):
    normalized_license_plate = models.CharField(
        max_length=20,
        db_index=True,
    )
    display_license_plate = models.CharField(
        max_length=20,
    )

    reason = models.TextField(blank=True)

    active = models.BooleanField(default=True)

    created_by_officer = models.ForeignKey(
        "accounts.Officer",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_license_plate_restrictions",
    )

    lifted_by_officer = models.ForeignKey(
        "accounts.Officer",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="lifted_license_plate_restrictions",
    )

    source_queue_entry = models.ForeignKey(
        "queueing.QueueEntry",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="license_plate_restrictions",
    )

    starts_at = models.DateTimeField(default=timezone.now)
    ends_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    lifted_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["normalized_license_plate"],
                condition=Q(active=True),
                name="unique_active_license_plate_restriction",
            )
        ]
        indexes = [
            models.Index(fields=["normalized_license_plate", "active"]),
            models.Index(fields=["active", "-created_at"]),
        ]

    def is_currently_active(self):
        now = timezone.now()

        if not self.active:
            return False

        if self.starts_at and self.starts_at > now:
            return False

        if self.ends_at and self.ends_at <= now:
            return False

        return True

    def lift(self, officer=None):
        self.active = False
        self.lifted_by_officer = officer
        self.lifted_at = timezone.now()
        self.save(
            update_fields=[
                "active",
                "lifted_by_officer",
                "lifted_at",
                "updated_at",
            ]
        )

    def __str__(self):
        return f"{self.display_license_plate} - {'active' if self.active else 'lifted'}"
