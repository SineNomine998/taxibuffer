from queueing.models import QueueEntry

ACTIVE_QUEUE_STATUSES = (QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED,)

CONTROL_DASHBOARD_CALLED_STATUSES = (
    QueueEntry.Status.NOTIFIED,
    QueueEntry.Status.DEQUEUED,
)
