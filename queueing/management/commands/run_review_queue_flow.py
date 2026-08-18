from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from queueing.models import QueueEntry, QueueNotification


class Command(BaseCommand):
    help = "Automatically drives Google Play review test queue entries."

    def handle(self, *args, **options):
        now = timezone.now()

        waiting_entries = QueueEntry.objects.select_related(
            "queue", "chauffeur"
        ).filter(
            status=QueueEntry.Status.WAITING,
            queue__is_test_queue=True,
            queue__review_auto_flow_enabled=True,
            chauffeur__is_review_account=True,
            created_at__lte=now - timedelta(seconds=45),
        )

        for entry in waiting_entries:
            try:
                entry.notify()
                self.stdout.write(f"Notified review entry {entry.uuid}")
            except Exception as exc:
                self.stderr.write(f"Could not notify {entry.uuid}: {exc}")

        notified_entries = QueueEntry.objects.select_related(
            "queue", "chauffeur"
        ).filter(
            status=QueueEntry.Status.NOTIFIED,
            queue__is_test_queue=True,
            queue__review_auto_flow_enabled=True,
            chauffeur__is_review_account=True,
            notified_at__lte=now - timedelta(seconds=90),
        )

        for entry in notified_entries:
            try:
                entry.dequeue()
                self.stdout.write(f"Completed review entry {entry.uuid}")
            except Exception as exc:
                self.stderr.write(f"Could not complete {entry.uuid}: {exc}")
