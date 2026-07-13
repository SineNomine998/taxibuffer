from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from queueing.models import QueueEntry
from mobile_api.push import send_location_lost_push


class Command(BaseCommand):
    help = "Remove waiting chauffeurs whose location heartbeat is missing too long."

    HEARTBEAT_TIMEOUT = timedelta(seconds=90)
    GRACE_PERIOD = timedelta(minutes=4)

    def handle(self, *args, **options):
        now = timezone.now()

        waiting_entries = QueueEntry.objects.select_related(
            "chauffeur", "queue"
        ).filter(status=QueueEntry.Status.WAITING)

        checked = 0
        warned = 0
        removed = 0

        for entry in waiting_entries:
            checked += 1

            if entry.last_location_at is None:
                missing_since = entry.created_at
            else:
                missing_since = entry.last_location_at

            heartbeat_missing = now - missing_since > self.HEARTBEAT_TIMEOUT

            if not heartbeat_missing:
                continue

            with transaction.atomic():
                locked_entry = QueueEntry.objects.select_for_update().get(id=entry.id)

                if locked_entry.status != QueueEntry.Status.WAITING:
                    continue

                if locked_entry.location_lost_at is None:
                    locked_entry.location_lost_at = now
                    locked_entry.location_warning_sent_at = now
                    locked_entry.save(
                        update_fields=[
                            "location_lost_at",
                            "location_warning_sent_at",
                        ]
                    )

                    transaction.on_commit(
                        lambda entry_id=locked_entry.id: send_location_lost_push(
                            entry_id
                        )
                    )

                    warned += 1
                    continue

                deadline = locked_entry.location_lost_at + self.GRACE_PERIOD

                if now >= deadline:
                    locked_entry.status = QueueEntry.Status.LEFT_ZONE
                    locked_entry.dequeued_at = now
                    locked_entry.save(
                        update_fields=[
                            "status",
                            "dequeued_at",
                        ]
                    )

                    removed += 1

        self.stdout.write(
            self.style.SUCCESS(f"Checked={checked}, warned={warned}, removed={removed}")
        )
