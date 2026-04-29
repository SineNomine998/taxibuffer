from django.http import JsonResponse
from queueing.models import PushSubscription
from queueing.push_views import send_web_push
from django.db.utils import ProgrammingError
from queueing.constants import CONTROL_DASHBOARD_CALLED_STATUSES

import logging

logger = logging.getLogger(__name__)


def send_notification_to_vehicle(vehicle_entry, is_busje=False):
    if vehicle_entry:
        vehicle_entry.notify()
        try:
            try:
                subs = PushSubscription.objects.filter(
                    chauffeur=vehicle_entry.chauffeur
                )

                if subs.exists():
                    payload = {
                        "title": "U bent aan de beurt",
                        "body": f"Ga naar ophaalzone: {vehicle_entry.queue.pickup_zone.name}",
                        "url": f"/queueing/queue/{vehicle_entry.uuid}/",
                        "tag": f"queue-{vehicle_entry.queue.id}",
                        "vibrate": [300, 100, 300],
                        "data": {
                            "url": f"/queueing/queue/{vehicle_entry.uuid}/",
                        },
                    }

                    for s in subs:
                        send_web_push(s.subscription_info, payload)
                        plate = vehicle_entry.license_plate or "unknown"
                        logger.info(
                            f"Push notification sent to {plate}"
                        )
                    # vehicle_entry.dequeue()
                else:
                    plate = vehicle_entry.license_plate or "unknown"
                    logger.warning(
                        f"No push subscriptions found for license plate: {plate}"
                    )

            except ProgrammingError:
                logger.warning("PushSubscription table does not exist yet")

        except Exception as push_exc:
            logger.exception(
                f"Failed to send web-push for vehicle_entry {vehicle_entry.id}: {push_exc}"
            )

        return {"success": True, "message": "Voertuig chauffeur opgeroepen!"}
    else:
        return {
            "success": False,
            "error": "Geen busjes gevonden in de wachtrij." if is_busje
                     else "Geen voertuigen gevonden in de wachtrij."
        }
