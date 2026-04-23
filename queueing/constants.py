from queueing.models import QueueEntry

ACTIVE_QUEUE_STATUSES = (QueueEntry.Status.WAITING,)

CONTROL_DASHBOARD_CALLED_STATUSES = (
    QueueEntry.Status.NOTIFIED,
    QueueEntry.Status.DEQUEUED,
)
