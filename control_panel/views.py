from django.utils import timezone
import pytz
from django.http import JsonResponse
from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.views import View
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.decorators import user_passes_test
from django.utils.decorators import method_decorator
from django.contrib.auth.mixins import LoginRequiredMixin
from accounts.models import Officer, User
from queueing.models import TaxiQueue, QueueEntry, PushSubscription
from queueing.push_views import send_web_push

from django.db.utils import ProgrammingError
import logging

logger = logging.getLogger(__name__)


class OfficerLoginView(View):
    """Handle officer authentication"""

    def get(self, request):
        """Display login form."""
        if request.user.is_authenticated and hasattr(request.user, "officer"):
            return redirect("control_panel:dashboard")

        context = {
            "show_access_denied": request.GET.get("access_denied") == "true",
        }
        return render(request, "control_panel/officer_login.html", context)

    def post(self, request):
        """Process login form."""
        first_name = request.POST.get("first-name", "").strip()
        last_name = request.POST.get("last-name", "").strip()
        credential = (
            f"{first_name} {last_name}".strip()
        )  # for now, we use the full name as credential

        # TODO: Add password handling and stuff in the future if needed
        if not first_name or not last_name:
            messages.error(request, "All fields are required.")
            return redirect("control_panel:login")

        try:
            # TODO: Try to find officer by credentials if authentication has more importance in the future
            officer = Officer.objects.filter(credentials=credential).first()

            # TODO: Handle authentication properly if needed in the future
            # if not officer:
            #     messages.error(request, "Invalid credentials.")
            #     return redirect("control_panel:login")

            if not officer:
                messages.info(request, "Officer not found. Creating new officer.")
                Officer.objects.create(
                    user=User.objects.create_user(
                        username=credential,
                        first_name=first_name,
                        last_name=last_name,
                        password="password",  # TODO: default password, change this later to handle authentication properly
                        is_officer=True,
                    ),
                    credentials=credential,
                )

            # Try to authenticate with the associated user
            user = authenticate(username=officer.user.username, password="password")

            if user is not None:
                login(request, user)
                return redirect("control_panel:dashboard")
            else:
                messages.error(request, "Invalid password.")
                return redirect("control_panel:login")

        except Exception as e:
            messages.error(request, f"Login failed: {str(e)}")
            return redirect("control_panel:login")


class OfficerLogoutView(View):
    """Handle officer logout"""

    def get(self, request):
        logout(request)
        return redirect("control_panel:login")


class OfficerDashboardView(LoginRequiredMixin, View):
    """Main dashboard for officers"""

    login_url = "/control/login/"

    def get(self, request):
        if not hasattr(request.user, "officer"):
            messages.error(request, "Access denied. Officer credentials required.")
            return redirect("control_panel:login")

        europe = pytz.timezone("Europe/Amsterdam")
        now_local = timezone.now().astimezone(europe)
        today_start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        today_start_utc = today_start_local.astimezone(pytz.UTC)

        queues = TaxiQueue.objects.filter(active=True).select_related(
            "buffer_zone", "pickup_zone"
        )

        for queue in queues:
            queue.dequeued_count = QueueEntry.objects.filter(
                queue=queue,
                status=QueueEntry.Status.DEQUEUED,
                dequeued_at__gte=today_start_utc,
            ).count()

        context = {"officer": request.user.officer, "queues": queues}
        return render(request, "control_panel/control_dashboard.html", context)


class QueueMonitorView(LoginRequiredMixin, View):
    """Display detailed queue status for a specific queue"""

    login_url = "/control/login/"

    def get(self, request, queue_id):
        if not hasattr(request.user, "officer"):
            messages.error(request, "Access denied. Officer credentials required.")
            return redirect("control_panel:login")

        europe = pytz.timezone("Europe/Amsterdam")
        now_local = timezone.now().astimezone(europe)
        today_start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        today_start_utc = today_start_local.astimezone(pytz.UTC)

        queue = TaxiQueue.objects.get(id=queue_id)

        # Get chauffeurs in different states - FILTERED FOR TODAY
        waiting_entries = queue.get_waiting_entries_control().filter(
            created_at__gte=today_start_utc
        )[:10]

        total_waiting_count = waiting_entries.count()

        notified_entries = QueueEntry.objects.filter(
            queue=queue,
            status=QueueEntry.Status.NOTIFIED,
            notified_at__gte=today_start_utc,
        ).order_by("-notified_at")

        dequeued_entries = QueueEntry.objects.filter(
            queue=queue,
            status=QueueEntry.Status.DEQUEUED,
            dequeued_at__gte=today_start_utc,
        ).order_by("-dequeued_at")[:20]

        total_dequeued_count = QueueEntry.objects.filter(
            queue=queue,
            status=QueueEntry.Status.DEQUEUED,
            dequeued_at__gte=today_start_utc,
        ).count()

        context = {
            "queue": queue,
            "waiting_entries": waiting_entries,
            "notified_entries": notified_entries,
            "dequeued_entries": dequeued_entries,
            "waiting_count": total_waiting_count,
            "notified_count": notified_entries.count(),
            "dequeued_count": total_dequeued_count,
        }
        return render(request, "control_panel/queue_monitor.html", context)


class QueueStatusAPIView(LoginRequiredMixin, View):
    """API endpoint for getting queue data"""

    login_url = "/control/login/"

    def get(self, request, queue_id):
        if not hasattr(request.user, "officer"):
            return JsonResponse({"success": False, "error": "Unauthorized"}, status=403)

        europe = pytz.timezone(
            "Europe/Amsterdam"
        )  # TODO? convert to Europe for now, change it later if necessary

        try:
            queue = TaxiQueue.objects.get(id=queue_id)

            now_local = timezone.now().astimezone(europe)
            today_start_local = now_local.replace(
                hour=0, minute=0, second=0, microsecond=0
            )
            today_start_utc = today_start_local.astimezone(
                pytz.UTC
            )  # Convert back to UTC for DB query

            # Filter for today's entries only (important)
            waiting_entries = list(
                queue.get_waiting_entries_control()
                .filter(created_at__gte=today_start_utc)
                .values(
                    "id", "uuid", "chauffeur__license_plate", "created_at", "status"
                )[:10]
            )

            total_waiting_count = (
                queue.get_waiting_entries_control()
                .filter(created_at__gte=today_start_utc)
                .count()
            )

            notified_entries = list(
                QueueEntry.objects.filter(
                    queue=queue,
                    status=QueueEntry.Status.NOTIFIED,
                    notified_at__gte=today_start_utc,
                )
                .order_by("-notified_at")
                .values(
                    "id", "uuid", "chauffeur__license_plate", "notified_at", "status"
                )
            )

            dequeued_entries = list(
                QueueEntry.objects.filter(
                    queue=queue,
                    status=QueueEntry.Status.DEQUEUED,
                    dequeued_at__gte=today_start_utc,
                )
                .order_by("-dequeued_at")[:20]
                .values(
                    "id", "uuid", "chauffeur__license_plate", "dequeued_at", "status"
                )
            )

            total_dequeued_count = QueueEntry.objects.filter(
                queue=queue,
                status=QueueEntry.Status.DEQUEUED,
                dequeued_at__gte=today_start_utc,
            ).count()

            # Format datetimes for display
            for entry in waiting_entries:
                if entry["created_at"]:
                    local_time = entry["created_at"].astimezone(europe)
                    entry["created_at"] = local_time.strftime("%H:%M:%S")

            for entry in notified_entries:
                if entry["notified_at"]:
                    local_time = entry["notified_at"].astimezone(europe)
                    entry["notified_at"] = local_time.strftime("%H:%M:%S")

            for entry in dequeued_entries:
                if entry["dequeued_at"]:
                    local_time = entry["dequeued_at"].astimezone(europe)
                    entry["dequeued_at"] = local_time.strftime("%H:%M:%S")

            last_updated_local = timezone.now().astimezone(europe)

            return JsonResponse(
                {
                    "success": True,
                    "waiting_entries": waiting_entries,
                    "notified_entries": notified_entries,
                    "dequeued_entries": dequeued_entries,
                    "waiting_count": total_waiting_count,
                    "notified_count": len(notified_entries),
                    "dequeued_count": total_dequeued_count,
                    "last_updated": last_updated_local.strftime("%H:%M:%S"),
                    "today_date": now_local.strftime("%d-%m-%Y"),
                }
            )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


# Simple check if user is an officer
def is_officer(user):
    return hasattr(user, "officer")


@method_decorator(user_passes_test(is_officer), name="dispatch")
class BypassBusjeView(View):
    """
    When an officer triggers this view, the first "busje" in the specified queue is popped
    and notified immediately. (hopefully :crossed_fingers:)
    """

    def post(self, request, queue_id):
        try:
            queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
            busje_entry = (
                queue.queueentry_set.filter(
                    status=QueueEntry.Status.WAITING, chauffeur__vehicle_type="busje"
                )
                .order_by("created_at")
                .first()
            )

            if busje_entry:
                busje_entry.notify()
                try:
                    try:
                        subs = PushSubscription.objects.filter(
                            chauffeur=busje_entry.chauffeur
                        )

                        if subs.exists():
                            payload = {
                                "title": "U bent aan de beurt",
                                "body": f"Ga naar ophaalzone: {busje_entry.queue.pickup_zone.name}",
                                "url": f"/queueing/queue/{busje_entry.uuid}/",
                                "tag": f"queue-{busje_entry.queue.id}",
                                "vibrate": [300, 100, 300],
                                "data": {
                                    "url": f"/queueing/queue/{busje_entry.uuid}/",
                                },
                            }

                            for s in subs:
                                send_web_push(s.subscription_info, payload)
                                logger.info(
                                    f"Push notification sent to {busje_entry.chauffeur.license_plate}"
                                )
                        else:
                            logger.warning(
                                f"No push subscriptions found for chauffeur {busje_entry.chauffeur.license_plate}"
                            )

                    except ProgrammingError:
                        logger.warning("PushSubscription table does not exist yet")

                except Exception as push_exc:
                    logger.exception(
                        f"Failed to send web-push for busje_entry {busje_entry.id}: {push_exc}"
                    )

                return JsonResponse(
                    {"success": True, "message": "Busje chauffeur notified!"}
                )
            else:
                return JsonResponse(
                    {"success": False, "error": "No busje chauffeur found in queue."}
                )
        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)
