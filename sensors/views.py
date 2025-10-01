import base64
import json
import logging
from datetime import timezone

import bcrypt
from django.http import JsonResponse
from django.utils import timezone as dj_timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods
from django.contrib.auth.hashers import check_password, make_password
from sensors.models import Sensor, SensorReading, ApiKey

logger = logging.getLogger(__name__)

# map string statuses to boolean for SensorReading.status (True = occupied)
STATUS_MAP = {
    "FREE": False,
    "BUSY": True,
    "OCCUPIED": True,
    "NOT_CALIBRATED": True,
    "UNKNOWN": True,
    # Everything accept "FREE" is treated as occupied to decrease false positive rates (i.e. falsely reporting free when occupied and sending notification)
}


def parse_timestamp(timestamp_string):
    """Parse 'YYYY-mm-dd HH:MM:SS' or ISO strings into aware datetime in default TZ."""
    if not timestamp_string:
        return dj_timezone.now()
    for format in ("%Y-%m-%d %H:%M:%S",):
        try:
            datetime = datetime.strptime(timestamp_string, format)
            datetime = datetime.replace(tzinfo=timezone.utc)
            return datetime.astimezone(dj_timezone.get_default_timezone())
        except Exception:
            continue
    try:
        # fallback ISO parse
        return dj_timezone.make_aware(datetime.fromisoformat(timestamp_string))
    except Exception:
        return dj_timezone.now()


def map_status(status_str):
    if status_str is None:
        return True  # default to occupied if missing
    status = str(status_str).strip().upper()
    if status in (
        "FREE",
        "VACANT",
        "EMPTY",
        "OPEN",
    ):  # I feel like spamming all possible phrases lol
        return False  # free (not occupied)
    if status in (
        "BUSY",
        "OCCUPIED",
        "TAKEN",
        "FULL",
        "NOT_CALIBRATED",
        "UNKNOWN",
        "N/A",
    ):
        return True  # not available || occupied
    return True  # default to occupied if unrecognized


@csrf_exempt
@require_http_methods(["POST"])
def sensor_data(request):
    """
    Endpoint for sensors to POST data.

    Auth:
      - Basic Auth: username=label, password=raw_key
      - Or: header 'Authorization' = raw_key and header 'label' = label
    """
    # TODO? Maybe I should've created separate functions for each step for clarity, oops ehehe
    # 1) extract auth
    auth_header = request.headers.get("Authorization")
    label_header = request.headers.get("label")
    label = None
    raw_key = None

    # Basic auth "Basic base64(label:raw_key)"
    if auth_header and auth_header.lower().startswith("basic "):
        try:
            encoded = auth_header.split(" ", 1)[1]
            decoded = base64.b64decode(encoded).decode("utf-8")
            label, raw_key = decoded.split(":", 1)
        except Exception:
            return JsonResponse(
                {"error": "Invalid Basic Authorization format"}, status=400
            )

    elif auth_header and label_header:
        # custom header auth: Authorization: raw_key and label: label
        label = label_header
        raw_key = auth_header

    else:
        return JsonResponse({"error": "Unauthorized - missing credentials"}, status=401)

    # 2) lookup ApiKey by label
    try:
        api_key_obj = ApiKey.objects.get(label=label)
    except ApiKey.DoesNotExist:
        return JsonResponse({"error": "Invalid label"}, status=401)
    except Exception as e:
        logger.exception("ApiKey lookup error: %s", e)
        return JsonResponse({"error": "Server error looking up API key"}, status=500)

    # 3) check password/hash (supports bcrypt -> migrate to Django hasher)
    try:
        stored = api_key_obj.key  # hashed password
        if stored and isinstance(stored, str) and stored.startswith("$2b$"):
            if bcrypt.checkpw(raw_key.encode("utf-8"), stored.encode("utf-8")):
                api_key_obj.key = make_password(raw_key)
                api_key_obj.save(update_fields=["key"])
            else:
                return JsonResponse({"error": "Unauthorized - invalid key"}, status=401)
        else:
            # Django hasher check
            if not check_password(raw_key, stored):
                return JsonResponse({"error": "Unauthorized - invalid key"}, status=401)
    except Exception as e:
        logger.exception("Password check error: %s", e)
        return JsonResponse(
            {"error": "Server error validating credentials"}, status=500
        )

    # 4) parse JSON body
    try:
        request_body = json.loads(request.body.decode("utf-8"))
    except json.JSONDecodeError:
        return JsonResponse({"error": "Invalid JSON"}, status=400)

    # 5) determine sensor_id (serial)
    sensor_id = request_body.get("sensor_info", {}).get("serial_number", None)

    if not sensor_id:
        return JsonResponse({"error": "Sensor ID missing"}, status=400)

    # 6) find Sensor (active)
    try:
        sensor = Sensor.objects.filter(sensor_id=sensor_id, active=True).first()
    except Exception as e:
        logger.exception("Sensor lookup failed: %s", e)
        return JsonResponse({"error": "Server error finding sensor"}, status=500)

    if not sensor:
        return JsonResponse({"error": "Sensor not found"}, status=404)

    # 7) map status & timestamp, save SensorReading (rounded to minute)
    try:
        status_bool = map_status(request_body.get("status"))
        timestamp = parse_timestamp(request_body.get("timestamp"))
        timestamp_rounded_to_minute = timestamp.replace(second=0, microsecond=0)  # round to minute
        print("PARSED TIMESTAMP:", timestamp)

        # avoid duplicate same-minute same-status
        last = SensorReading.objects.filter(sensor=sensor).order_by("-date").first()
        print("IS 'LAST' TRUE:", last is not None)
        if (
            last
            and last.date.replace(second=0, microsecond=0) == timestamp_rounded_to_minute
            and last.status == status_bool
        ):
            # duplicate; nothing to save
            return JsonResponse(
                {"status": "no_change", "message": "Duplicate reading in same minute"},
                status=200,
            )

        sensor_reading = SensorReading(
            sensor=sensor, date=timestamp, status=status_bool
        )
        sensor_reading.save()
    except Exception as e:
        logger.exception("Failed saving SensorReading: %s", e)
        return JsonResponse({"error": "Server error saving reading"}, status=500)

    return JsonResponse({"status": "success"}, status=200)
