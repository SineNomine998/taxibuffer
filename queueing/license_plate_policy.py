from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from .activity import log_chauffeur_activity

from queueing.models import QueueEntry, LicensePlateRestriction, ChauffeurActivityLog


def normalize_license_plate_for_policy(license_plate):
    return "".join(char for char in str(license_plate or "").upper() if char.isalnum())


def get_active_license_plate_restriction(license_plate):
    normalized = normalize_license_plate_for_policy(license_plate)

    if not normalized:
        return None

    now = timezone.now()

    return (
        LicensePlateRestriction.objects.filter(
            normalized_license_plate=normalized,
            active=True,
            starts_at__lte=now,
        )
        .filter(Q(ends_at__isnull=True) | Q(ends_at__gt=now))
        .first()
    )


@transaction.atomic
def block_license_plate(
    *,
    license_plate,
    officer=None,
    reason="",
    source_queue_entry=None,
    remove_waiting_entries=True,
):
    normalized = normalize_license_plate_for_policy(license_plate)

    if not normalized:
        raise ValueError("License plate is required.")

    existing = get_active_license_plate_restriction(license_plate)

    if existing:
        return existing, False, 0

    restriction = LicensePlateRestriction.objects.create(
        normalized_license_plate=normalized,
        display_license_plate=license_plate,
        reason=reason,
        created_by_officer=officer,
        source_queue_entry=source_queue_entry,
    )

    removed_count = 0

    if remove_waiting_entries:
        now = timezone.now()

        matching_entries = QueueEntry.objects.select_for_update().filter(
            status=QueueEntry.Status.WAITING,
            normalized_license_plate_snapshot=normalized,
        )

        for entry in matching_entries:
            entry.status = QueueEntry.Status.BLOCKED
            entry.dequeued_at = now
            entry.save(update_fields=["status", "dequeued_at", "updated_at"])
            log_chauffeur_activity(
                chauffeur=entry.chauffeur,
                queue=entry.queue,
                queue_entry=entry,
                event_type=ChauffeurActivityLog.EventType.BLOCKED,
                title="Kenteken geblokkeerd",
                message=f"Het kenteken {normalized} is geblokkeerd. Daarom bent u uit de wachtrij gehaald.",
                queue_position=entry.get_queue_position(),
            )
            removed_count += 1

    return restriction, True, removed_count


@transaction.atomic
def lift_license_plate_restriction(*, restriction, officer=None):
    restriction.lift(officer=officer)
    return restriction
