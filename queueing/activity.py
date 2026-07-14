from .models import ChauffeurActivityLog


def log_chauffeur_activity(
    *,
    chauffeur,
    event_type,
    title,
    message="",
    queue=None,
    queue_entry=None,
    queue_position=None,
    previous_queue_position=None,
    sequence_number=None,
    lat=None,
    lng=None,
    metadata=None,
):
    return ChauffeurActivityLog.objects.create(
        chauffeur=chauffeur,
        event_type=event_type,
        title=title,
        message=message,
        queue=queue,
        queue_entry=queue_entry,
        queue_position=queue_position,
        previous_queue_position=previous_queue_position,
        sequence_number=sequence_number,
        lat=lat,
        lng=lng,
        metadata=metadata or {},
    )
