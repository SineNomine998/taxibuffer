from django.db.utils import ProgrammingError
from django.utils import timezone
from django.db import transaction
from django.contrib.gis.geos import Point
from typing import Tuple
from django.db.models import Avg, F
import logging

from .models import TaxiQueue, QueueEntry, QueueNotification, PushSubscription
from accounts.models import Chauffeur
from .push_views import send_web_push


logger = logging.getLogger(__name__)


class QueueService:
    """Service class for handling queue operations and business logic."""

    def mock_geofencing_check(self, location: Point, buffer_zone) -> bool:
        """
        Mock geofencing function for testing.
        In production, this would check if location is within buffer_zone.zone
        For now, always returns True.
        """
        return True

    def add_chauffeur_to_queue(
        self, chauffeur: Chauffeur, queue: TaxiQueue, signup_location: Point
    ) -> Tuple[bool, str]:
        """
        Add a chauffeur to the specified queue.

        Returns:
            Tuple[bool, str]: (success, message)
        """
        try:
            with transaction.atomic():
                # Check if chauffeur is already in any active queue
                queue = TaxiQueue.objects.select_for_update().get(id=queue.id)

                existing_entry = QueueEntry.objects.filter(
                    chauffeur=chauffeur,
                    status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
                ).first()
                print("\nDEBUG Existing entry:", existing_entry, "\n")

                if existing_entry:
                    return (
                        False,
                        f"You are already in queue: {existing_entry.queue.name}",
                        existing_entry.uuid,
                    )

                # Mock geofencing check
                if not self.mock_geofencing_check(signup_location, queue.buffer_zone):
                    return (
                        False,
                        "You must be in the buffer zone to join the queue.",
                        None,
                    )

                # Create queue entry
                entry = QueueEntry.objects.create(
                    queue=queue,
                    chauffeur=chauffeur,
                    signup_location=signup_location,
                    status=QueueEntry.Status.WAITING,
                )

                position = entry.get_queue_position()
                return (
                    True,
                    f"Successfully joined queue! Your position: {position}",
                    entry.uuid,
                )

        except Exception as e:
            logger.error(f"Error adding chauffeur to queue: {e}")
            return False, f"Failed to join queue: {str(e)}"

    def delete_dequeued_chauffeur(
        self, chauffeur: Chauffeur, queue: TaxiQueue, signup_location: Point
    ) -> Tuple[bool, str]:
        try:
            # TODO! Remove old logic (safely :pray:)
            with transaction.atomic():
                entry = QueueEntry.objects.filter(
                    chauffeur=chauffeur,
                    queue=queue,
                    status__in=[
                        QueueEntry.Status.LEFT_ZONE,
                        # QueueEntry.Status.DECLINED,
                        QueueEntry.Status.DEQUEUED,
                        # QueueEntry.Status.TIMEOUT,
                    ],
                ).first()

                if not entry:
                    return False, "You are still in a queue."

                entry.delete()

                return (
                    True,
                    "Successfully dequeued from the queue and deleted from the system.",
                )

        except Exception as e:
            logger.error(f"Error deleting chauffeur: {e}")
            return False, f"Failed to delete the chauffeur: {str(e)}"

    def notify_next_chauffeurs(
        self, queue: TaxiQueue, slots_available: int, options=None
    ) -> int:
        """
        Notify the next N chauffeurs in queue that slots are available.

        Returns:
            int: Number of chauffeurs notified
        """
        if slots_available <= 0:
            return 0

        # Default options
        if options is None:
            options = {"send_push": True}

        try:
            # Get next chauffeurs in queue
            next_entries = queue.get_next_in_queue(count=slots_available)
            notified_count = 0

            for entry in next_entries:
                try:
                    with transaction.atomic():
                        # Check if chauffeur is still in waiting status
                        if entry.status == QueueEntry.Status.WAITING:
                            notification = entry.notify()
                            logger.info(
                                f"Notified chauffeur {entry.chauffeur.license_plate}"
                            )
                            notified_count += 1

                            # Only send web push if option is enabled
                            if options.get("send_push", True):
                                try:
                                    try:
                                        subs = PushSubscription.objects.filter(
                                            chauffeur=entry.chauffeur
                                        )

                                        if subs.exists():
                                            payload = {
                                                "title": "U bent aan de beurt",
                                                "body": f"Ga naar ophaalzone: {entry.queue.pickup_zone.name}",
                                                "url": f"/queueing/queue/{entry.uuid}/",
                                                "tag": f"queue-{entry.queue.id}",
                                                "vibrate": [300, 100, 300],
                                                "data": {
                                                    "url": f"/queueing/queue/{entry.uuid}/",
                                                },
                                            }

                                            for s in subs:
                                                send_web_push(
                                                    s.subscription_info, payload
                                                )
                                                logger.info(
                                                    f"Push notification sent to {entry.chauffeur.license_plate}"
                                                )
                                        else:
                                            logger.warning(
                                                f"No push subscriptions found for chauffeur {entry.chauffeur.license_plate}"
                                            )

                                    except ProgrammingError:
                                        logger.warning(
                                            "PushSubscription table does not exist yet"
                                        )

                                except Exception as push_exc:
                                    logger.exception(
                                        f"Failed to send web-push for entry {entry.id}: {push_exc}"
                                    )

                except Exception as e:
                    logger.error(
                        f"Failed to notify chauffeur {entry.chauffeur.license_plate}: {e}"
                    )
                    continue

            return notified_count

        except Exception as e:
            logger.error(f"Error notifying chauffeurs: {e}")
            return 0

    def process_queue_notifications(self, queue: TaxiQueue) -> int:
        """
        Process the queue and notify chauffeurs if slots are available.
        This simulates sensor detection of available slots.

        Returns:
            int: Number of chauffeurs notified
        """
        try:
            # Mock sensor data - simulate checking pickup zone occupancy
            mock_available_slots = self.get_mock_available_slots(queue.pickup_zone)

            if mock_available_slots > 0:
                return self.notify_next_chauffeurs(queue, mock_available_slots)

            return 0

        except Exception as e:
            logger.error(f"Error processing queue notifications: {e}")
            return 0

    def get_mock_available_slots(self, pickup_zone) -> int:
        """
        Mock function to get available slots in pickup zone.
        In production, this would check actual sensor data.

        For now, returns a random number between 0-2 for testing.
        """
        import random

        # Get currently dequeued entries (taxis that should be in pickup zone)
        from django.db.models import Q

        recent_dequeued = QueueEntry.objects.filter(
            queue__pickup_zone=pickup_zone,
            status=QueueEntry.Status.DEQUEUED,
            dequeued_at__gte=timezone.now() - timezone.timedelta(minutes=30),
        ).count()

        # Assume pickup zone can hold 7 taxis maximum
        max_capacity = getattr(pickup_zone, "total_sensors", 7)
        occupied = min(recent_dequeued, max_capacity)
        available = max(0, max_capacity - occupied)

        # Add some randomness for testing
        return min(available, random.randint(0, 2))

    def handle_notification_timeouts(self, queue: TaxiQueue = None) -> int:
        """
        Handle notification timeouts for chauffeurs who didn't respond.

        Args:
            queue: Specific queue to check, or None for all queues

        Returns:
            int: Number of notifications timed out
        """
        timeout_count = 0

        try:
            # TODO! Remove old logic (safely :pray:) 
            # Get all pending notifications that have expired
            queryset = QueueNotification.objects.filter(
                response=QueueNotification.ResponseType.PENDING
            ).select_related("queue_entry", "queue_entry__queue")

            if queue:
                queryset = queryset.filter(queue_entry__queue=queue)

            for notification in queryset:
                if notification.is_expired():
                    try:
                        with transaction.atomic():
                            # Mark the notification as timed out - this will also
                            # update the queue entry status back to WAITING
                            notification.respond(QueueNotification.ResponseType.TIMEOUT)
                            logger.info(
                                f"Timed out notification for {notification.queue_entry.chauffeur.license_plate}"
                            )
                            timeout_count += 1

                            # This slot is now available again, so we can notify the next person in line
                            # But we only notify if there are other people in the queue
                            # (this avoids notifying the same person who just timed out)
                            queue = notification.queue_entry.queue
                            waiting_entries = queue.get_waiting_entries()

                            # Find the next entry that's not the one that just timed out
                            next_entries = [
                                entry
                                for entry in waiting_entries
                                if entry.chauffeur.id
                                != notification.queue_entry.chauffeur.id
                            ]

                            if next_entries:
                                # There's someone else in the queue, so we notify them
                                self.notify_next_chauffeurs(
                                    queue,
                                    1,
                                    {
                                        "send_push": True,
                                    },
                                )

                    except Exception as e:
                        logger.error(f"Error handling timeout: {e}")
                        continue

            return timeout_count

        except Exception as e:
            logger.error(f"Error handling notification timeouts: {e}")
            return 0

    def get_queue_statistics(self, queue: TaxiQueue) -> dict:
        """
        Get comprehensive queue statistics.

        Returns:
            dict: Queue statistics
        """
        try:
            waiting_count = queue.get_waiting_entries().count()
            notified_count = queue.entries.filter(
                status=QueueEntry.Status.NOTIFIED
            ).count()
            dequeued_count = queue.get_recently_dequeued().count()

            avg_wait_time = queue.entries.filter(
                status__in=[
                    QueueEntry.Status.DEQUEUED,
                    # QueueEntry.Status.DECLINED,
                    # QueueEntry.Status.TIMEOUT,
                ]
            ).aggregate(
                avg_minutes=Avg(
                    (F("notified_at") - F("created_at"))
                    / (1000000 * 60)  # Convert microseconds to minutes
                )
            )[
                "avg_minutes"
            ]

            return {
                "queue_name": queue.name,
                "waiting": waiting_count,
                "notified": notified_count,
                "recently_dequeued": dequeued_count,
                "average_wait_minutes": round(avg_wait_time or 0, 1),
                "last_updated": timezone.now().isoformat(),
            }

        except Exception as e:
            logger.error(f"Error getting queue statistics: {e}")
            return {
                "error": str(e),
                "last_updated": timezone.now().isoformat(),
            }
