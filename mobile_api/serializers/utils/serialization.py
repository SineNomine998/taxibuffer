def serialize_queue(queue):
    waiting_count = queue.get_waiting_entries().count()

    pickup_zone = getattr(queue, "pickup_zone", None)
    buffer_zone = getattr(queue, "buffer_zone", None)

    return {
        "queue_id": queue.id,
        "name": getattr(pickup_zone, "name", None) or str(queue),
        "address": getattr(pickup_zone, "address", None),
        "is_active": queue.active,
        "waiting_count": waiting_count,
        "buffer_zone_name": getattr(buffer_zone, "name", None),
        "image_url": None,
    }


def serialize_waiting_entry(entry, current_chauffeur_id):
    return {
        "first_name": entry.chauffeur.user.first_name,
        "license_plate": entry.display_license_plate,
        "is_current_chauffeur": entry.chauffeur_id == current_chauffeur_id,
        "position": entry.get_queue_position(),
    }


def serialize_notification(notification):
    if notification is None:
        return None

    return {
        "id": notification.id,
        "notification_time": (
            notification.notification_time.isoformat()
            if notification.notification_time
            else None
        ),
        "sequence_number": notification.sequence_number,
    }
