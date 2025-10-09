from django.core.management.base import BaseCommand
from queueing.models import TaxiQueue


class Command(BaseCommand):
    help = "Resets next_notification_number to 1 for all active queues"

    def handle(self, *args, **kwargs):
        queues = TaxiQueue.objects.filter(active=True)
        for queue in queues:
            queue.next_notification_number = 1
            queue.save(update_fields=["next_notification_number"])
        self.stdout.write(
            self.style.SUCCESS("Reset sequence numbers for all active queues")
        )
