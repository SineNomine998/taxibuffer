from .models import QueueEntry
from .push_views import send_location_ping
from .constants import ACTIVE_QUEUE_STATUSES

def ping_all_active_entries():
    """
    Called every 60 seconds.
    Sends a LOCATION_PING to all active queue entries.
    """
    active_entries = QueueEntry.objects.filter(status__in=ACTIVE_QUEUE_STATUSES)

    for entry in active_entries:
        send_location_ping(entry)
