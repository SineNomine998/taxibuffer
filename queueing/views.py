from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from django.views import View
from django.urls import reverse
from django.contrib.gis.geos import Point
from django.utils import timezone
from django.db import transaction
import json
from django.conf import settings
from django.http import FileResponse
import re
import os
import logging

from accounts.models import Chauffeur, User
from geofence.models import BufferZone, PickupZone
from .models import TaxiQueue, QueueEntry, QueueNotification, PushSubscription
from .services import QueueService
from .push_views import send_web_push

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
                # Create a dummy test chauffeur
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
            request.session.pop("form_data", None)
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
            messages.error(request, "Invalid RTX number format.")
            return redirect("queueing:chauffeur_login")

        try:
            with transaction.atomic():
                # Check if chauffeur already exists
                try:
                    chauffeur = Chauffeur.objects.get(license_plate=license_plate)
                    # Verify taxi license matches
                    if chauffeur.taxi_license_number != taxi_license_number:
                        messages.error(
                            request,
                            "License plate and taxi license number do not match.",
                        )
                        return redirect("queueing:chauffeur_login")
                except Chauffeur.DoesNotExist:
                    # Create new user and chauffeur
                    user = User.objects.create_user(
                        username=f"chauffeur_{license_plate.lower().replace('-', '_')}",
                        is_chauffeur=True,
                    )
                    chauffeur = Chauffeur.objects.create(
                        user=user,
                        license_plate=license_plate,
                        taxi_license_number=taxi_license_number,
                        location=None,  # Will be set when joining queue
                    )

                # Store chauffeur info in session for step 2
                request.session["authenticated_chauffeur_id"] = chauffeur.id
                request.session.pop("form_data", None)  # Clear form data
                return redirect("queueing:location_selection")

        except Exception as e:
            print("BRO WHAT'S THE ISSUE???")
            print(e)
            messages.error(request, f"Authentication failed: {str(e)}")
            return redirect("queueing:chauffeur_login")

    def validate_license_plate_format(self, license_plate):
        """Validate license plate format (basic validation)."""

        # TODO: Double check the Dutch license plate formats: 1-ABC-23, AB-123-C, etc.
        patterns = [
            r"^[A-Z]{2}-\d{2}-\d{2}$",  # XX-99-99
            r"^\d{2}-\d{2}-[A-Z]{2}$",  # 99-99-XX
            r"^[A-Z]{2}-\d{2}-[A-Z]{2}$",  # XX-99-XX
            r"^\d{2}-[A-Z]{2}-\d{2}$",  # 99-XX-99
            r"^[A-Z]{2}-[A-Z]{2}-\d{2}$",  # XX-XX-99
            r"^\d{2}-[A-Z]{2}-[A-Z]{2}$",  # 99-XX-XX
            r"^[A-Z]{1}-\d{3}-[A-Z]{2}$",  # X-999-XX
            r"^[A-Z]{2}-\d{3}-[A-Z]{1}$",  # XX-999-X
            r"^\d{3}-[A-Z]{2}-[A-Z]{1}$",  # 999-XX-X
            r"^\d{3}-[A-Z]{1}-[A-Z]{2}$",  # 999-X-XX
            r"^\d{1,2}-[A-Z]{2,3}-\d{1,2}$",  # 1-ABC-23
            r"^\d{3}-[A-Z]{2}-\d{1,2}$",  # 123-AB-1
            r"^[A-Z]{3}-\d{2}-\d{1,2}$",  # ABC-12-3
        ]
        return any(re.match(pattern, license_plate) for pattern in patterns)

    # TODO: Validate RTX numbers with a proper pattern if available in the future (if necessary)
    def validate_taxi_license_format(self, taxi_license):
        """Validate taxi license format (basic validation)."""
        return True
        # Basic format: letters and numbers, 3-20 characters
        return re.match(r"^[A-Z0-9]{3,20}$", taxi_license) is not None


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
                    # "is_expired": notification.is_expired(),
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

        context = {
            "chauffeur": chauffeur,
            "queues": active_queues,
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

        # TODO: Change this mock location for real geofencing logic
        mock_location = Point(
            4.9036, 52.3676
        )  # Amsterdam coordinates if I'm not mistaken

        try:
            queue_service = QueueService()
            success, message, entry_uuid = queue_service.add_chauffeur_to_queue(
                chauffeur=chauffeur, queue=queue, signup_location=mock_location
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
                    return redirect("queueing:location_selection")
            else:
                logger.debug(message)
                return redirect("queueing:queue_status", entry_uuid=entry_uuid)

        except Exception as e:
            logger.error(f"Failed to join queue: {str(e)}")
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
