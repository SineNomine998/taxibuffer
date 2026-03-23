from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from django.views import View
from django.urls import reverse
from django.contrib.gis.geos import Point
from django.utils import timezone
from django.utils.safestring import mark_safe
from django.db import transaction
import json
from django.conf import settings
from django.http import FileResponse
import re
import os
import logging

from accounts.models import Chauffeur, User
from .models import TaxiQueue, QueueEntry, QueueNotification
from .services import QueueService
from geofence.services import point_in_buffer, make_point_from_lat_lng

logger = logging.getLogger(__name__)


class InfoPagesView(View):
    """Serves informational pages regarding this taxi buffer system TaxiBuffer."""

    def get(self, request):
        """Display info page."""
        step = int(request.session.get("info_step", 1))
        print("CURRENT INFO STEP:", step)
        context = {"step": step}
        return render(request, "queueing/info_pages.html", context)

    def post(self, request):
        """Handle navigation between info pages."""
        step = int(request.session.get("info_step", 1))

        if step < 2:
            step += 1
            request.session["info_step"] = step
            return redirect(reverse("queueing:info_pages"))
        else:
            request.session.pop("info_step", None)
            return redirect("queueing:chauffeur_login")


class ChauffeurLoginView(View):
    """Handle chauffeur authentication (Step 1)"""

    def get(self, request):
        """Display login form."""
        context = {
            "show_access_denied": request.GET.get("access_denied") == "true",
            "form_data": request.session.get("form_data", {}),
        }
        return render(request, "queueing/chauffeur_login.html", context)

    def post(self, request):
        """Process login form."""
        license_plate = request.POST.get("license_plate", "").strip().upper()
        taxi_license_number = (
            request.POST.get("taxi_license_number", "").strip().upper()
        )

        # Store form data in session for redisplay
        request.session["form_data"] = {
            "license_plate": license_plate,
            "taxi_license_number": taxi_license_number,
        }

        # Bypass check for testing purposes
        if license_plate == "SINENOMINE" and taxi_license_number == "TEST":
            try:
                chauffeur = Chauffeur.objects.get(license_plate="SINENOMINE")
            except Chauffeur.DoesNotExist:
                user = User.objects.create_user(
                    username="test_chauffeur", is_chauffeur=True
                )
                chauffeur = Chauffeur.objects.create(
                    user=user,
                    license_plate="SINENOMINE",
                    taxi_license_number="TEST",
                    location=None,
                )
            request.session["authenticated_chauffeur_id"] = chauffeur.id
            return redirect("queueing:location_selection")

        # Basic validation
        if not all([license_plate, taxi_license_number]):
            messages.error(request, "All fields are required.")
            return redirect("queueing:chauffeur_login")

        # Basic format validation
        if not self.validate_license_plate_format(license_plate):
            messages.error(request, "Invalid license plate format.")
            return redirect("queueing:chauffeur_login")

        if not self.validate_taxi_license_format(taxi_license_number):
            messages.error(request, "Invalid RTX number format.", extra_tags="RTX")
            return redirect("queueing:chauffeur_login")

        try:
            with transaction.atomic():
                # Fetch all chauffeurs with the same license plate
                matching_chauffeurs = Chauffeur.objects.filter(license_plate=license_plate)
                # Get the chauffeur with matching RTX-number, if any
                chauffeur = matching_chauffeurs.filter(taxi_license_number=taxi_license_number).first()

                if not chauffeur:
                    if matching_chauffeurs.exists():
                        # Create new chauffeur with different RTX-number for the same vehicle.
                        username = f"chauffeur_{license_plate.lower().replace('-', '_')}_{taxi_license_number.lower()}"
                        user = User.objects.create_user(username=username, is_chauffeur=True)
                        chauffeur = Chauffeur.objects.create(
                            user=user,
                            license_plate=license_plate,
                            taxi_license_number=taxi_license_number,
                            location=None,
                        )
                    else:
                        # If no chauffeur with this license plate exists at all, create one normally.
                        username = f"chauffeur_{license_plate.lower().replace('-', '_')}"
                        user = User.objects.create_user(username=username, is_chauffeur=True)
                        chauffeur = Chauffeur.objects.create(
                            user=user,
                            license_plate=license_plate,
                            taxi_license_number=taxi_license_number,
                            location=None,
                        )

                request.session["authenticated_chauffeur_id"] = chauffeur.id
                return redirect("queueing:location_selection")

        except Exception as e:
            print("BRO WHAT'S THE ISSUE???")
            print(e)
            messages.error(request, f"Authentication failed: {str(e)}")
            return redirect("queueing:chauffeur_login")

    def validate_license_plate_format(self, license_plate):
        """Validate license plate format (basic validation)."""
        return True

        # TODO: Double check the Dutch license plate formats: 1-ABC-23, AB-123-C, etc.
        # Apparently, there are quite a few valid formats (excluding these ones), so for now we don't check the format at all
        # patterns = [
        #     r"^[A-Z]{2}-\d{2}-\d{2}$",  # XX-99-99
        #     r"^\d{2}-\d{2}-[A-Z]{2}$",  # 99-99-XX
        #     r"^[A-Z]{2}-\d{2}-[A-Z]{2}$",  # XX-99-XX
        #     r"^\d{2}-[A-Z]{2}-\d{2}$",  # 99-XX-99
        #     r"^[A-Z]{2}-[A-Z]{2}-\d{2}$",  # XX-XX-99
        #     r"^\d{2}-[A-Z]{2}-[A-Z]{2}$",  # 99-XX-XX
        #     r"^[A-Z]{1}-\d{3}-[A-Z]{2}$",  # X-999-XX
        #     r"^[A-Z]{2}-\d{3}-[A-Z]{1}$",  # XX-999-X
        #     r"^\d{3}-[A-Z]{2}-[A-Z]{1}$",  # 999-XX-X
        #     r"^\d{3}-[A-Z]{1}-[A-Z]{2}$",  # 999-X-XX
        #     r"^\d{1,2}-[A-Z]{2,3}-\d{1,2}$",  # 1-ABC-23
        #     r"^\d{3}-[A-Z]{2}-\d{1,2}$",  # 123-AB-1
        #     r"^[A-Z]{3}-\d{2}-\d{1,2}$",  # ABC-12-3
        # ]
        # return any(re.match(pattern, license_plate) for pattern in patterns)

    def validate_taxi_license_format(self, taxi_license):
        """Validate taxi license format.

        Allowed formats:
            - DDDD      (4 digits)
            - DDDDD     (5 digits)
            - DDDD-XD   (4 digits, a dash, one letter, one digit)
        """
        pattern = r"^(?:\d{4}|\d{5}|\d{4}-[A-Za-z]\d)$"
        return bool(re.fullmatch(pattern, taxi_license))


class LocationSelectionInfoView(View):
    def get(self, request):
        return render(request, "queueing/location_selection_info.html")


class SignUpStep1View(View):
    """Signup step 1: collect profile basics."""

    template_name = "queueing/sign_up1.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        context = {
            "form_data": {
                "first_name": flow.get("first_name", ""),
                "last_name": flow.get("last_name", ""),
                "rtx_number": flow.get("rtx_number", ""),
            }
        }
        return render(request, self.template_name, context)

    def post(self, request):
        first_name = request.POST.get("first_name", "").strip()
        last_name = request.POST.get("last_name", "").strip()
        rtx_number = request.POST.get("rtx_number", "").strip().upper()

        if not all([first_name, last_name, rtx_number]):
            messages.error(request, "Vul alle verplichte velden in.")
            return redirect("queueing:sign_up1")

        flow = request.session.get("signup_flow", {})
        flow["first_name"] = first_name
        flow["last_name"] = last_name
        flow["rtx_number"] = rtx_number
        flow.setdefault("vehicles", [])
        request.session["signup_flow"] = flow

        return redirect("queueing:sign_up2")


class SignUpPasswordView(View):
    """Signup step 2: set account password."""

    template_name = "queueing/sign_up2_password.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")
        return render(request, self.template_name)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        password = request.POST.get("password", "")
        password_repeat = request.POST.get("password_repeat", "")

        if not password or not password_repeat:
            messages.error(request, "Vul beide wachtwoordvelden in.")
            return redirect("queueing:sign_up2")

        if password != password_repeat:
            messages.error(request, "Wachtwoorden komen niet overeen.")
            return redirect("queueing:sign_up2")

        if len(password) < 8:
            messages.error(request, "Kies een wachtwoord van minimaal 8 tekens.")
            return redirect("queueing:sign_up2")

        flow["raw_password"] = password
        request.session["signup_flow"] = flow

        return redirect("queueing:sign_up3")


class SignUpVehicleView(View):
    """Signup step 3: select current vehicle and finish."""

    template_name = "queueing/sign_up3_vehicle.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        vehicles = flow.get("vehicles", [])
        current_index = flow.get("current_vehicle_index")
        if current_index is None and vehicles:
            current_index = 0
            flow["current_vehicle_index"] = 0
            request.session["signup_flow"] = flow

        current_vehicle = None
        other_vehicles = []
        if vehicles and current_index is not None and 0 <= current_index < len(vehicles):
            current_vehicle = vehicles[current_index]
            other_vehicles = [
                {"vehicle": v, "index": i}
                for i, v in enumerate(vehicles)
                if i != current_index
            ]

        context = {
            "current_vehicle": current_vehicle,
            "other_vehicles": other_vehicles,
            "has_vehicles": len(vehicles) > 0,
        }
        return render(request, self.template_name, context)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        action = request.POST.get("action", "finish")
        vehicles = flow.get("vehicles", [])

        if action == "set_current":
            index = request.POST.get("vehicle_index", "")
            try:
                index = int(index)
            except (ValueError, TypeError):
                messages.error(request, "Kon huidig voertuig niet instellen.")
                return redirect("queueing:sign_up3")

            if 0 <= index < len(vehicles):
                flow["current_vehicle_index"] = index
                request.session["signup_flow"] = flow
            return redirect("queueing:sign_up3")

        if action == "remove_vehicle":
            index = request.POST.get("vehicle_index", "")
            try:
                index = int(index)
            except (ValueError, TypeError):
                messages.error(request, "Kon voertuig niet verwijderen.")
                return redirect("queueing:sign_up3")

            if 0 <= index < len(vehicles):
                vehicles.pop(index)
                flow["vehicles"] = vehicles

                current_index = flow.get("current_vehicle_index")
                if not vehicles:
                    flow["current_vehicle_index"] = None
                elif current_index is None:
                    flow["current_vehicle_index"] = 0
                elif current_index == index:
                    flow["current_vehicle_index"] = 0
                elif current_index > index:
                    flow["current_vehicle_index"] = current_index - 1

                request.session["signup_flow"] = flow
            return redirect("queueing:sign_up3")

        if not vehicles:
            messages.error(request, "Voeg minimaal 1 voertuig toe om verder te gaan.")
            return redirect("queueing:sign_up3")

        current_index = flow.get("current_vehicle_index")
        if current_index is None or current_index >= len(vehicles):
            flow["current_vehicle_index"] = 0

        request.session["signup_flow"] = flow
        messages.success(
            request,
            "Accountaanvraag opgeslagen in sessie. Koppel backend-opslag om dit definitief te maken.",
        )
        return redirect("queueing:chauffeur_login")


class SignUpAddVehicleView(View):
    """Sub-step from step 3 for adding one vehicle."""

    template_name = "queueing/sign_up_vehicle_add.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")
        return render(request, self.template_name)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        license_plate = request.POST.get("license_plate", "").strip().upper()
        nickname = request.POST.get("nickname", "").strip()
        set_as_current = request.POST.get("set_as_current") == "on"

        if not license_plate or not nickname:
            messages.error(request, "Vul kenteken en bijnaam in.")
            return redirect("queueing:sign_up_vehicle_add")

        vehicles = flow.get("vehicles", [])
        vehicles.append({"license_plate": license_plate, "nickname": nickname})
        flow["vehicles"] = vehicles

        if set_as_current or len(vehicles) == 1:
            flow["current_vehicle_index"] = len(vehicles) - 1

        request.session["signup_flow"] = flow
        return redirect("queueing:sign_up3")


class QueueStatusView(View):
    """Display queue status for a specific chauffeur."""

    def get(self, request, entry_uuid):
        """Display queue status page."""
        try:
            # Get the specific queue entry by UUID
            entry = get_object_or_404(QueueEntry, uuid=entry_uuid)
            queue = entry.queue
            chauffeur = entry.chauffeur

            context = {
                "queue": queue,
                "chauffeur": chauffeur,
                "entry": entry,
                "vapid_public_key": settings.WEBPUSH_SETTINGS["VAPID_PUBLIC_KEY"],
            }
            return render(request, "queueing/queue_status.html", context)

        except Exception as e:
            messages.error(request, f"Invalid queue entry: {str(e)}")
            return redirect("queueing:chauffeur_login")


class QueueStatusAPIView(View):
    """API endpoint for live queue status updates."""

    def get(self, request, entry_uuid):
        """Return JSON with current queue status."""
        try:
            entry = QueueEntry.objects.get(uuid=entry_uuid)
            queue = entry.queue

            # Get queue position and waiting count
            position = entry.get_queue_position()
            waiting_entries = queue.get_waiting_entries()
            total_waiting = waiting_entries.count()

            # Get pending notifications
            pending_notifications = QueueNotification.objects.filter(
                queue_entry=entry, response=QueueNotification.ResponseType.PENDING
            ).order_by("-notification_time")

            has_pending_notification = pending_notifications.exists()
            notification_data = None

            if has_pending_notification:
                notification = pending_notifications.first()
                notification_data = {
                    "id": notification.id,
                    "notification_time": notification.notification_time.isoformat(),
                    "sequence_number": notification.sequence_number,
                }

            return JsonResponse(
                {
                    "success": True,
                    "status": entry.get_status_display(),
                    "status_code": entry.status,
                    "position": position,
                    "total_waiting": total_waiting,
                    "has_notification": has_pending_notification,
                    "notification": notification_data,
                    "sequence_number": notification_data.get("sequence_number") if notification_data else None,
                    "last_updated": timezone.now().isoformat(),
                }
            )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


class LeaveQueueBeforeNotificationAPIView(View):
    """Allow chauffeurs to leave the queue voluntarily before receiving any notification."""

    @method_decorator(csrf_exempt)
    def dispatch(self, *args, **kwargs):
        return super().dispatch(*args, **kwargs)

    def post(self, request, entry_uuid):
        try:
            entry = get_object_or_404(QueueEntry, uuid=entry_uuid)

            # Check if entry is active (i.e. waiting or notified)
            if entry.status in [QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED]:
                entry.status = QueueEntry.Status.LEFT_ZONE
                entry.dequeued_at = timezone.now()
                entry.save()

                return JsonResponse(
                    {"success": True, "message": "Successfully left the queue."}
                )
            else:
                return JsonResponse(
                    {"success": False, "error": "Entry is no longer active."}
                )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


class LocationSelectionView(View):
    """Handle location selection (Step 2)"""

    def get(self, request):
        """Display location selection."""
        chauffeur_uuid = request.session.get("authenticated_chauffeur_id")
        if not chauffeur_uuid:
            logger.warning("Please authenticate first.")
            return redirect("queueing:chauffeur_login")

        try:
            chauffeur = Chauffeur.objects.get(id=chauffeur_uuid)

            # Check if chauffeur is already in an active queue
            active_entry = QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
            ).first()

            if active_entry:
                # If they're already in a queue, redirect them to that queue's status page
                return redirect("queueing:queue_status", entry_uuid=active_entry.uuid)

        except Chauffeur.DoesNotExist:
            logger.warning("Invalid session. Please authenticate again.")
            return redirect("queueing:chauffeur_login")

        active_queues = TaxiQueue.objects.filter(active=True).select_related(
            "buffer_zone", "pickup_zone"
        )

        for queue in active_queues:
            queue.waiting_count = queue.get_waiting_entries().count()

        form_data = request.session.get("form_data", {})
        context = {
            "chauffeur": chauffeur,
            "queues": active_queues,
            "form_data": form_data,
        }
        return render(request, "queueing/location_selection.html", context)

    def post(self, request):
        """Process location selection and join queue."""
        chauffeur_id = request.session.get("authenticated_chauffeur_id")
        if not chauffeur_id:
            logger.warning("Please authenticate first.")
            return redirect("queueing:chauffeur_login")

        selected_queue_id = request.POST.get("selected_queue_id")
        if not selected_queue_id:
            logger.warning("Please select a pickup location.")
            return redirect("queueing:location_selection")

        try:
            chauffeur = Chauffeur.objects.get(id=chauffeur_id)
            queue = TaxiQueue.objects.get(id=selected_queue_id, active=True)
        except (Chauffeur.DoesNotExist, TaxiQueue.DoesNotExist):
            logger.warning("Invalid selection. Please try again.")
            return redirect("queueing:location_selection")

        latitude = request.POST.get("signup_lat")
        longitude = request.POST.get("signup_lng")
        signup_point = None

        if latitude and longitude:
            try:
                latitude = float(latitude)
                longitude = float(longitude)
                signup_point = make_point_from_lat_lng(latitude, longitude, srid=4326)
            except ValueError:
                logger.warning("Invalid latitude/longitude values.")
                messages.error(
                    request, "Invalid location coordinates.", extra_tags="location"
                )
                return redirect("queueing:location_selection")
        else:
            logger.warning("Missing latitude/longitude values.")
            messages.error(
                request, "Location coordinates are required.", extra_tags="location"
            )
            return redirect("queueing:location_selection")

        if signup_point is None and getattr(chauffeur, "location", None):
            signup_point = chauffeur.location

        if signup_point is None:
            logger.warning("Could not determine signup location.")
            messages.error(
                request,
                "Kon uw locatie niet bepalen. Schakel locatievoorziening in en probeer opnieuw.",
                extra_tags="location",
            )
            return redirect("queueing:location_selection")
        

        admin_license_plate = request.session.get("form_data", {}).get("license_plate", "").upper()
        buffer_zone = getattr(queue, "buffer_zone", None)
        if buffer_zone and getattr(buffer_zone, "zone", None):
            try:
                if 'point_in_buffer' in globals() and callable(point_in_buffer):
                    inside = point_in_buffer(buffer_zone, signup_point.y, signup_point.x, inclusive=True)
                else:
                    inside = buffer_zone.zone.intersects(signup_point)
            except Exception as e:
                logger.exception("Geofence spatial check failed: %s", e)
                inside = False

            # Allow admin override for testing :)
            if not inside and admin_license_plate != "SINENOMINE":
                messages.error(
                    request,
                    mark_safe(f"U bevindt zich nog niet in de buurt van bufferzone <strong>{buffer_zone.name}</strong> en kunt u dus nog niet aanmelden voor de wachtrij."),
                    extra_tags="geofence",
                )
                return redirect("queueing:location_selection")
        else:
            logger.warning("Queue %s has no buffer zone defined; allowing join", queue.id)

        try:
            queue_service = QueueService()
            success, message, entry_uuid = queue_service.add_chauffeur_to_queue(
                chauffeur=chauffeur, queue=queue, signup_location=signup_point
            )

            if success:
                entry = (
                    QueueEntry.objects.filter(
                        queue=queue,
                        chauffeur=chauffeur,
                        status__in=[
                            QueueEntry.Status.WAITING,
                            QueueEntry.Status.NOTIFIED,
                        ],
                    )
                    .order_by("-created_at")
                    .first()
                )

                if entry:
                    logger.debug(message)
                    return redirect("queueing:queue_status", entry_uuid=entry.uuid)
                else:
                    logger.warning("Failed to retrieve queue entry.")
                    messages.error(request, "Er is iets misgegaan. Neem contact op met de beheerder.")
                    return redirect("queueing:location_selection")
            else:
                logger.debug(message)
                messages.error(request, message or "Kon niet aanmelden :(")
                return redirect("queueing:queue_status", entry_uuid=entry_uuid)

        except Exception as e:
            logger.error(f"Failed to join queue: {str(e)}")
            messages.error(request, "Er is iets misgegaan bij het aanmelden. Probeer later opnieuw.")
            return redirect("queueing:location_selection")


@method_decorator(csrf_exempt, name="dispatch")
class NotificationResponseView(View):
    """Handle chauffeur responses to notifications."""

    def post(self, request):
        """Process notification response."""
        try:
            data = json.loads(request.body)
            notification_id = data.get("notification_id")
            response_type = data.get("response")

            if not all([notification_id, response_type]):
                return JsonResponse(
                    {"success": False, "error": "Missing required fields"}, status=400
                )

            if response_type not in ["accepted", "declined"]:
                return JsonResponse(
                    {"success": False, "error": "Invalid response type"}, status=400
                )

            notification = get_object_or_404(QueueNotification, id=notification_id)

            if notification.response != QueueNotification.ResponseType.PENDING:
                return JsonResponse(
                    {
                        "success": False,
                        "error": "Notification has already been responded to",
                    },
                    status=400,
                )

            if response_type == "accepted":
                notification.respond(QueueNotification.ResponseType.ACCEPTED)
                message = "Drive safely :)"

            return JsonResponse({"success": True, "message": message})

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=500)


class SetVehicleTypeView(View):
    def post(self, request):
        vt = request.POST.get("vehicle_type") or (
            request.body and json.loads(request.body).get("vehicle_type")
        )
        if vt not in ("auto", "busje"):
            return JsonResponse(
                {"success": False, "error": "invalid vehicle_type"}, status=400
            )
        try:
            chauffeur_id = request.session.get("authenticated_chauffeur_id")
            if chauffeur_id:
                chauffeur = Chauffeur.objects.get(id=chauffeur_id)
            else:
                if not request.user.is_authenticated or not hasattr(
                    request.user, "chauffeur"
                ):
                    return JsonResponse(
                        {
                            "success": False,
                            "error": "User not authenticated as chauffeur",
                        },
                        status=403,
                    )
            print("BRO DO WE HAVE A PROPER CHAUFFEUR?\n", chauffeur)
            chauffeur.vehicle_type = vt
            chauffeur.save(update_fields=["vehicle_type"])
            return JsonResponse({"success": True, "vehicle_type": vt})
        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=500)


# Manual trigger view for testing/admin purposes
class ManualTriggerView(View):
    """Manual trigger for testing - simulates sensor detection of available slots."""

    def get(self, request, queue_id):
        """Display manual trigger form."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)

        context = {
            "queue": queue,
            "waiting_count": queue.get_waiting_entries().count(),
        }
        return render(request, "queueing/manual_trigger.html", context)

    def post(self, request, queue_id):
        """Process manual trigger."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
        slots_available = int(request.POST.get("slots_available", 1))
        send_push = request.POST.get("send_push") == "1"

        try:
            queue_service = QueueService()
            notification_options = {
                "send_push": send_push,
            }

            notified_count = queue_service.notify_next_chauffeurs(
                queue, slots_available, notification_options
            )

            if notified_count > 0:
                print(f"Notified {notified_count} chauffeur(s) to proceed.")
            else:
                print("No chauffeurs in queue to notify.")

        except Exception as e:
            print(f"Error: {str(e)}")

        return redirect("queueing:manual_trigger", queue_id=queue_id)

    def validate_taxi_license_format(self, taxi_license):
        """Validate taxi license format (basic validation)."""

        # Basic format: letters and numbers, 3-20 characters
        return re.match(r"^[A-Z0-9]{3,20}$", taxi_license) is not None


def service_worker(request):
    """Serve service worker from root URL"""
    # Path to the service worker file in the static folder
    sw_path = os.path.join(
        settings.BASE_DIR, "queueing", "static", "queueing", "js", "sw.js"
    )

    # Serve the file with the correct mime type
    response = FileResponse(open(sw_path, "rb"), content_type="application/javascript")

    # Add cache control headers
    response["Service-Worker-Allowed"] = "/"
    response["Cache-Control"] = "no-cache"

    return response
