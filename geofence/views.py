import json
from django.http import JsonResponse
from django.views import View
from .services import point_in_buffer
import logging
from django.utils.safestring import mark_safe

from queueing.models import TaxiQueue

logger = logging.getLogger(__name__)


class ValidateLocationView(View):
    def post(self, request):
        try:
            data = json.loads(request.body)
            # Bypass geofence check for testing purposes if license_plate is "SINENOMINE" :)
            if data.get("license_plate") == "SINENOMINE":
                return JsonResponse({"is_valid": True})
        except ValueError:
            return JsonResponse(
                {"is_valid": False, "error_message": "Invalid JSON data."}, status=400
            )

        selected_queue_id = data.get("selected_queue_id")
        if not selected_queue_id:
            return JsonResponse(
                {
                    "is_valid": False,
                    "error_message": "Pickup location (selected_queue_id) is missing.",
                },
                status=400,
            )

        try:
            queue = TaxiQueue.objects.get(id=selected_queue_id, active=True)
        except TaxiQueue.DoesNotExist:
            return JsonResponse(
                {
                    "is_valid": False,
                    "error_message": "Ongeldige of inactieve ophaallocatie.",
                },
                status=400,
            )

        try:
            lat = data.get("lat")
            lng = data.get("lng")

            if lat is None or lng is None:
                return JsonResponse(
                    {"is_valid": False, "error_message": "Locatiegegevens ontbreken."},
                    status=400,
                )
            lat = float(lat)
            lng = float(lng)
        except (ValueError, TypeError):
            return JsonResponse(
                {"is_valid": False, "error_message": "Ongeldige locatiegegevens."},
                status=400,
            )

        buffer_zone = getattr(queue, "buffer_zone", None)
        if not buffer_zone or not getattr(buffer_zone, "zone", None):
            return JsonResponse(
                {
                    "is_valid": False,
                    "error_message": "Er is geen bufferzone voor de geselecteerde locatie.",
                },
                status=400,
            )

        try:
            valid = point_in_buffer(buffer_zone, lat, lng, inclusive=True)
        except Exception as e:
            logger.exception("Geofence check failed: %s", e)
            return JsonResponse(
                {"is_valid": False, "error_message": "Fout tijdens geofence-controle."},
                status=500,
            )

        if valid:
            return JsonResponse({"is_valid": True})
        else:
            return JsonResponse(
                {
                    "is_valid": False,
                    "error_message": mark_safe(
                        f"U bevindt zich nog niet in de buurt van bufferzone <strong>{buffer_zone.name}</strong> en kunt u dus nog niet aanmelden voor de wachtrij."
                    ),
                },
                status=400,
            )
