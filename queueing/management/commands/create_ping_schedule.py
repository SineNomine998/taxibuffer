from django.core.management.base import BaseCommand
from django_q.tasks import schedule
from django_q.models import Schedule

class Command(BaseCommand):
    help = "Create the periodic LOCATION_PING schedule if it doesn't exist"

    def handle(self, *args, **kwargs):
        if not Schedule.objects.filter(func="queueing.tasks.ping_all_active_entries").exists():
            schedule(
                "queueing.tasks.ping_all_active_entries",
                schedule_type=Schedule.MINUTES,
                minutes=1,
            )
            self.stdout.write(self.style.SUCCESS("Created ping schedule"))
        else:
            self.stdout.write("Ping schedule already exists")
