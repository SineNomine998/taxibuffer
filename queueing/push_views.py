import json
from django.views.decorators.csrf import csrf_exempt
from django.http import JsonResponse
from django.conf import settings
from pywebpush import webpush, WebPushException
from .models import PushSubscription
from .models import QueueEntry
from urllib.parse import urlparse
import logging

logger = logging.getLogger(__name__)


@csrf_exempt
def push_subscribe(request):
    if request.method != "POST":
        return JsonResponse({"success": False}, status=405)
    body = json.loads(request.body.decode("utf-8"))
    subscription = body.get("subscription")
    entry_uuid = body.get("entry_uuid")

    chauffeur = None
    if entry_uuid:
        try:
            entry = QueueEntry.objects.get(uuid=entry_uuid)
            chauffeur = entry.chauffeur
        except QueueEntry.DoesNotExist:
            entry = None

    endpoint = subscription.get("endpoint")
    if endpoint:
        PushSubscription.objects.filter(subscription_info__endpoint=endpoint).delete()

    PushSubscription.objects.create(
        chauffeur=chauffeur, subscription_info=subscription, entry_uuid=entry_uuid
    )
    return JsonResponse({"success": True})


def send_web_push(subscription_info, payload, ttl=0):
    try:
        logger.info(f"Sending push notification: {payload}")
        logger.info(f"To subscription: {subscription_info}")

        # Extract the audience from the endpoint
        endpoint = subscription_info.get("endpoint", "")
        audience = None

        # Parse the endpoint URL to extract the origin
        if endpoint:
            parsed_url = urlparse(endpoint)
            audience = f"{parsed_url.scheme}://{parsed_url.netloc}"

        # Create vapid claims with the correct audience
        vapid_claims = {
            "sub": settings.WEBPUSH_SETTINGS["VAPID_CLAIMS"]["sub"],
            "aud": audience,
        }

        logger.debug(f"Payload: {payload}")
        logger.debug(f"Subscription info: {subscription_info}")
        logger.debug(f"VAPID claims: {vapid_claims}")

        response = webpush(
            subscription_info=subscription_info,
            data=json.dumps(payload),
            vapid_private_key=settings.WEBPUSH_SETTINGS["VAPID_PRIVATE_KEY"],
            vapid_claims=vapid_claims,
            ttl=ttl,  # default is 0, but configurable
            headers={"x-wns-cache-policy": "no-cache" if ttl == 0 else "cache"},
        )

        logger.info(f"Push sent successfully: {response.status_code}")

        return True

    except WebPushException as ex:
        # More detailed error logging
        logger.error(f"WebPushException: {ex}")
        if hasattr(ex, "response") and ex.response:
            logger.error(f"Response status: {ex.response.status_code}")
            logger.error(f"Response body: {ex.response.text}")

            # If subscription is gone/invalid, remove it
            if ex.response.status_code in (404, 410):
                PushSubscription.objects.filter(
                    subscription_info__endpoint=subscription_info.get("endpoint")
                ).delete()
                logger.warning(
                    f"Deleted invalid subscription with endpoint: {subscription_info.get('endpoint')}"
                )
        return False
    except Exception as e:
        logger.error(f"General push error: {e}")
        logger.error("Push notification failed", exc_info=True)
        return False


@csrf_exempt
def test_push(request):
    """Test endpoint to send a push notification to a specific entry"""
    if request.method != "POST":
        return JsonResponse(
            {"success": False, "error": "Method not allowed"}, status=405
        )

    try:
        data = json.loads(request.body.decode("utf-8"))
        entry_uuid = data.get("entry_uuid")

        if not entry_uuid:
            return JsonResponse({"success": False, "error": "Missing entry_uuid"})

        # Get the entry and associated subscriptions
        try:
            entry = QueueEntry.objects.get(uuid=entry_uuid)
            subs = PushSubscription.objects.filter(chauffeur=entry.chauffeur)

            if not subs.exists():
                return JsonResponse(
                    {
                        "success": False,
                        "error": "No push subscriptions found for this chauffeur",
                        "subscriptions_count": 0,
                    }
                )

            # Send a test notification to all subscriptions
            success_count = 0
            for sub in subs:
                payload = {
                    "title": "Test Notification",
                    "body": f"This is a test push from the server to {entry.chauffeur.license_plate}",
                    "url": f"/queueing/queue/{entry_uuid}/",
                    "tag": f"test-{entry_uuid}",
                    "vibrate": [
                        300,
                        100,
                        300,
                    ],  # no clue how this feels on a real phone
                    "data": {"url": f"/queueing/queue/{entry_uuid}/"},
                }

                if send_web_push(sub.subscription_info, payload):
                    success_count += 1

            return JsonResponse(
                {
                    "success": True,
                    "message": f"Push sent to {success_count} of {subs.count()} subscriptions",
                }
            )

        except QueueEntry.DoesNotExist:
            return JsonResponse({"success": False, "error": "Invalid entry UUID"})

    except Exception as e:
        logger.error("Error occurred while testing push notification", exc_info=True)
        return JsonResponse({"success": False, "error": str(e)})
