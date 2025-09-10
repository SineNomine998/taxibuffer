from django.utils import timezone
import pytz
from django.http import JsonResponse
from django.shortcuts import render, redirect
from django.contrib import messages
from django.views import View
from django.contrib.auth import authenticate, login, logout
from django.contrib.auth.mixins import LoginRequiredMixin
from accounts.models import Officer, User
from queueing.models import TaxiQueue, QueueEntry


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

        # Get all active queues
        queues = TaxiQueue.objects.filter(active=True).select_related(
            "buffer_zone", "pickup_zone"
        )

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
        waiting_entries = queue.get_waiting_entries().filter(
            created_at__gte=today_start_utc
        )

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

        context = {
            "queue": queue,
            "waiting_entries": waiting_entries,
            "notified_entries": notified_entries,
            "dequeued_entries": dequeued_entries,
            "waiting_count": waiting_entries.count(),
            "notified_count": notified_entries.count(),
            "dequeued_count": dequeued_entries.count(),
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

            # Filter for today's entries only
            waiting_entries = list(
                queue.get_waiting_entries()
                .filter(created_at__gte=today_start_utc)
                .values(
                    "id", "uuid", "chauffeur__license_plate", "created_at", "status"
                )
            )

            notified_entries = list(
                QueueEntry.objects.filter(
                    queue=queue,
                    status=QueueEntry.Status.NOTIFIED,
                    notified_at__gte=today_start_utc,
                ).values(
                    "id", "uuid", "chauffeur__license_plate", "notified_at", "status"
                )
            )

            dequeued_entries = list(
                QueueEntry.objects.filter(
                    queue=queue,
                    status=QueueEntry.Status.DEQUEUED,
                    dequeued_at__gte=today_start_utc,
                )
                .order_by("-dequeued_at")
                .values(
                    "id", "uuid", "chauffeur__license_plate", "dequeued_at", "status"
                )[:20]
            )

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
                    "waiting_count": len(waiting_entries),
                    "notified_count": len(notified_entries),
                    "dequeued_count": len(dequeued_entries),
                    "last_updated": last_updated_local.strftime("%H:%M:%S"),
                    "today_date": now_local.strftime("%d-%m-%Y"),
                }
            )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)
