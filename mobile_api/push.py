import logging

import firebase_admin
from django.conf import settings
from firebase_admin import credentials, messaging

from mobile_api.models import MobilePushToken
from queueing.models import QueueNotification, QueueEntry

logger = logging.getLogger(__name__)


def ensure_firebase_initialized():
    if firebase_admin._apps:
        return

    cred = credentials.Certificate(settings.FIREBASE_SERVICE_ACCOUNT_PATH)
    firebase_admin.initialize_app(cred)


def send_queue_called_push(notification_id):
    ensure_firebase_initialized()

    notification = QueueNotification.objects.select_related(
        "queue_entry__chauffeur"
    ).get(id=notification_id)

    entry = notification.queue_entry
    chauffeur = entry.chauffeur

    tokens = list(
        MobilePushToken.objects.filter(
            chauffeur=chauffeur,
            active=True,
        ).values_list("token", flat=True)
    )

    if not tokens:
        logger.warning(
            "No active FCM tokens for chauffeur_id=%s entry_uuid=%s",
            chauffeur.id,
            entry.uuid,
        )
        return

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title="U mag doorrijden",
            body="U bent aan de beurt. Rij naar de ophaallocatie.",
        ),
        data={
            "type": "queue_called",
            "entry_uuid": str(entry.uuid),
            "notification_id": str(notification.id),
            "sequence_number": str(notification.sequence_number or ""),
        },
    )

    response = messaging.send_each_for_multicast(message)

    logger.info(
        "FCM queue_called sent entry_uuid=%s success=%s failure=%s",
        entry.uuid,
        response.success_count,
        response.failure_count,
    )


def send_location_lost_push(entry_id):
    ensure_firebase_initialized()

    entry = QueueEntry.objects.select_related("chauffeur", "queue").get(id=entry_id)
    chauffeur = entry.chauffeur

    tokens = list(
        MobilePushToken.objects.filter(
            chauffeur=chauffeur,
            active=True,
        ).values_list("token", flat=True)
    )

    if not tokens:
        logger.warning(
            "No active FCM tokens for location lost chauffeur_id=%s entry_uuid=%s",
            chauffeur.id,
            entry.uuid,
        )
        return

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title="Locatie niet beschikbaar",
            body=("Open TaxiBuffer en zet locatie aan om in de wachtrij te blijven."),
        ),
        data={
            "type": "location_lost",
            "entry_uuid": str(entry.uuid),
            "queue_id": str(entry.queue_id),
            "reason": "location_unavailable",
        },
    )

    response = messaging.send_each_for_multicast(message)

    logger.info(
        "FCM location_lost sent entry_uuid=%s success=%s failure=%s",
        entry.uuid,
        response.success_count,
        response.failure_count,
    )


def send_test_push_to_chauffeur(chauffeur):
    ensure_firebase_initialized()

    tokens = list(
        MobilePushToken.objects.filter(
            chauffeur=chauffeur,
            active=True,
        ).values_list("token", flat=True)
    )

    if not tokens:
        logger.warning(
            "No active FCM tokens for test push chauffeur_id=%s",
            chauffeur.id,
        )
        return {
            "success": False,
            "message": "Geen actief push-token gevonden.",
        }

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(
            title="Pushmeldingen werken goed",
            body="U ontvangt meldingen van TaxiBuffer correct.",
        ),
        data={
            "type": "test_push",
        },
    )

    response = messaging.send_each_for_multicast(message)

    logger.info(
        "FCM test_push sent chauffeur_id=%s success=%s failure=%s",
        chauffeur.id,
        response.success_count,
        response.failure_count,
    )

    return {
        "success": response.success_count > 0,
        "success_count": response.success_count,
        "failure_count": response.failure_count,
    }
