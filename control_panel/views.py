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
from accounts.models import ChauffeurVehicle, Officer, User
from control_panel.services import send_notification_to_vehicle
from queueing.models import (
    QueueNotification,
    TaxiQueue,
    QueueEntry,
    LicensePlateRestriction,
)
from queueing.license_plate_policy import (
    block_license_plate,
    lift_license_plate_restriction,
)
from django.db.models import (
    Subquery,
    OuterRef,
    IntegerField,
    Count,
    Q,
    Case,
    When,
    F,
    Value,
    CharField,
    DateTimeField,
)
from django.db.utils import ProgrammingError
from queueing.constants import CONTROL_DASHBOARD_CALLED_STATUSES

import logging

logger = logging.getLogger(__name__)


class ControlLoginRequiredMixin(LoginRequiredMixin):
    """Custom mixin."""

    login_url = "/control/login/"


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
            if not officer:
                messages.error(request, "Invalid credentials.")
                return redirect("control_panel:login")

            # if not officer:
            #     messages.info(request, "Officer not found. Creating new officer.")
            #     Officer.objects.create(
            #         user=User.objects.create_user(
            #             username=credential,
            #             first_name=first_name,
            #             last_name=last_name,
            #             password="password",  # TODO: default password, change this later to handle authentication properly
            #             is_officer=True,
            #         ),
            #         credentials=credential,
            #     )

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


class OfficerDashboardView(ControlLoginRequiredMixin, View):
    """Main dashboard for officers"""

    def get(self, request):
        if not hasattr(request.user, "officer"):
            messages.error(request, "Access denied. Officer credentials required.")
            return redirect("control_panel:login")

        europe = pytz.timezone("Europe/Amsterdam")
        now_local = timezone.now().astimezone(europe)
        today_start_local = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
        today_start_utc = today_start_local.astimezone(pytz.UTC)

        queues = TaxiQueue.objects.select_related(
            "buffer_zone", "pickup_zone"
        ).annotate(
            waiting_count=Count(
                "queueentry",
                filter=Q(
                    queueentry__status=QueueEntry.Status.WAITING,
                    queueentry__created_at__gte=today_start_utc,
                ),
                distinct=True,
            ),
            called_count=Count(
                "queueentry",
                filter=(
                    Q(queueentry__status__in=CONTROL_DASHBOARD_CALLED_STATUSES)
                    & (
                        Q(queueentry__notified_at__gte=today_start_utc)
                        | Q(queueentry__dequeued_at__gte=today_start_utc)
                    )
                ),
                distinct=True,
            ),
        )

        context = {"officer": request.user.officer, "queues": queues}
        return render(request, "control_panel/control_dashboard.html", context)


class QueueMonitorView(ControlLoginRequiredMixin, View):
    """Display detailed queue status for a specific queue"""

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
        )

        total_waiting_count = waiting_entries.count()

        latest_notification_seq = Subquery(
            QueueNotification.objects.filter(queue_entry=OuterRef("pk"))
            .order_by("-notification_time")
            .values("sequence_number")[:1],
            output_field=IntegerField(),
        )

        called_qs = (
            QueueEntry.objects.filter(
                queue=queue,
                status__in=CONTROL_DASHBOARD_CALLED_STATUSES,
            )
            .filter(
                Q(notified_at__gte=today_start_utc)
                | Q(dequeued_at__gte=today_start_utc)
            )
            .annotate(
                sequence_number=latest_notification_seq,
                display_time=Case(
                    When(status=QueueEntry.Status.DEQUEUED, then=F("dequeued_at")),
                    default=F("notified_at"),
                    output_field=DateTimeField(),
                ),
                display_status=Case(
                    When(status=QueueEntry.Status.DEQUEUED, then=Value("Dequeued")),
                    default=Value("Notified"),
                    output_field=CharField(),
                ),
            )
            .order_by("-display_time")
        )

        called_entries = list(
            called_qs.values(
                "id",
                "uuid",
                "license_plate_snapshot",
                "status",
                "display_status",
                "sequence_number",
                "display_time",
            )
        )

        called_count = called_qs.count()

        context = {
            "queue": queue,
            "waiting_entries": waiting_entries,
            "called_entries": called_entries,
            "waiting_count": total_waiting_count,
            "called_count": called_count,
        }
        return render(request, "control_panel/queue_monitor.html", context)


class QueueStatusAPIView(ControlLoginRequiredMixin, View):
    """API endpoint for getting queue data"""

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

            latest_notification_seq = Subquery(
                QueueNotification.objects.filter(queue_entry=OuterRef("pk"))
                .order_by("-notification_time")
                .values("sequence_number")[:1],
                output_field=IntegerField(),
            )

            # Filter for today's waiting entries only (important)
            waiting_qs = (
                queue.get_waiting_entries_control()
                .filter(created_at__gte=today_start_utc)
                .order_by("created_at")
            )

            waiting_entries = list(
                waiting_qs.values(
                    "id",
                    "uuid",
                    "license_plate_snapshot",
                    "created_at",
                    "status",
                )
            )

            total_waiting_count = waiting_qs.count()

            called_qs = (
                QueueEntry.objects.filter(
                    queue=queue,
                    status__in=CONTROL_DASHBOARD_CALLED_STATUSES,
                )
                .filter(
                    Q(notified_at__gte=today_start_utc)
                    | Q(dequeued_at__gte=today_start_utc)
                )
                .annotate(
                    sequence_number=latest_notification_seq,
                    display_time=Case(
                        When(status=QueueEntry.Status.DEQUEUED, then=F("dequeued_at")),
                        default=F("notified_at"),
                        output_field=DateTimeField(),
                    ),
                    display_status=Case(
                        When(status=QueueEntry.Status.DEQUEUED, then=Value("Dequeued")),
                        default=Value("Notified"),
                        output_field=CharField(),
                    ),
                )
                .order_by("-display_time")
            )

            called_entries = list(
                called_qs.values(
                    "id",
                    "uuid",
                    "license_plate_snapshot",
                    "status",
                    "sequence_number",
                    "display_status",
                    "display_time",
                )
            )

            # Aging implementation for notified entries (to prevent and visualise false negatives in unmarked but arrived chauffeurs)
            now = timezone.now()

            for entry in called_entries:
                raw_entry = QueueEntry.objects.filter(id=entry["id"]).first()

                if (
                    raw_entry
                    and raw_entry.status == QueueEntry.Status.NOTIFIED
                    and raw_entry.notified_at
                ):
                    entry["notified_age_seconds"] = int(
                        (now - raw_entry.notified_at).total_seconds()
                    )
                else:
                    entry["notified_age_seconds"] = None

            # Format datetimes for display
            for entry in waiting_entries:
                if entry["created_at"]:
                    local_time = entry["created_at"].astimezone(europe)
                    entry["created_at"] = local_time.strftime("%H:%M:%S")

            for entry in called_entries:
                if entry["display_time"]:
                    local_time = entry["display_time"].astimezone(europe)
                    entry["display_time"] = local_time.strftime("%H:%M:%S")

            last_updated_local = timezone.now().astimezone(europe)

            return JsonResponse(
                {
                    "success": True,
                    "waiting_entries": waiting_entries,
                    "called_entries": called_entries,
                    "waiting_count": total_waiting_count,
                    "called_count": called_qs.count(),
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
class PauseQueueView(View):
    """Toggle pause state for a specific queue"""

    def post(self, request, queue_id):
        queue = get_object_or_404(TaxiQueue, id=queue_id)
        action = request.POST.get("action")  # 'pause' or 'resume'
        if action == "pause":
            queue.notifications_paused = True
            queue.save(update_fields=["notifications_paused"])
        elif action == "resume":
            queue.notifications_paused = False
            queue.save(update_fields=["notifications_paused"])
        else:
            return JsonResponse(
                {"success": False, "error": "invalid action"}, status=400
            )
        return JsonResponse(
            {"success": True, "notifications_paused": queue.notifications_paused}
        )


@method_decorator(user_passes_test(is_officer), name="dispatch")
class ToggleQueueActivationView(View):
    """Activate or deactivate a specific queue"""

    def post(self, request, queue_id):
        queue = get_object_or_404(TaxiQueue, id=queue_id)
        action = request.POST.get("action")
        if action == "activate":
            queue.active = True
            queue.save(update_fields=["active"])
        elif action == "deactivate":
            queue.active = False
            queue.save(update_fields=["active"])
        else:
            return JsonResponse(
                {"success": False, "error": "invalid action"}, status=400
            )
        return JsonResponse({"success": True, "active": queue.active})


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
                    status=QueueEntry.Status.WAITING, vehicle_type="busje"
                )
                .order_by("created_at")
                .first()
            )

            result = send_notification_to_vehicle(busje_entry, True)
            return JsonResponse(result)
        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


@method_decorator(user_passes_test(is_officer), name="dispatch")
class BypassVehicleView(View):
    """
    When an officer triggers this view, the first vehicle ("voertuig") in the specified queue is popped
    and notified immediately. (hopefully :crossed_fingers:)
    """

    def post(self, request, queue_id):
        try:
            queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
            vehicle_entry = (
                queue.queueentry_set.filter(
                    status=QueueEntry.Status.WAITING,
                )
                .order_by("created_at")
                .first()
            )

            result = send_notification_to_vehicle(vehicle_entry, False)
            return JsonResponse(result)
        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


@method_decorator(user_passes_test(is_officer), name="dispatch")
class MarkEntryDequeuedView(View):
    """
    Officer marks a notified chauffeur as arrived/handled at pickup.
    This is the official NOTIFIED -> DEQUEUED transition.
    """

    def post(self, request, queue_id, entry_id):
        try:
            queue = get_object_or_404(TaxiQueue, id=queue_id)

            entry = get_object_or_404(
                QueueEntry,
                id=entry_id,
                queue=queue,
                status=QueueEntry.Status.NOTIFIED,
            )

            entry.status = QueueEntry.Status.DEQUEUED
            entry.dequeued_at = timezone.now()
            entry.save(update_fields=["status", "dequeued_at", "updated_at"])

            return JsonResponse(
                {
                    "success": True,
                    "message": f"{entry.license_plate_snapshot} is gemarkeerd als aangekomen.",
                    "entry_id": entry.id,
                    "status": entry.status,
                }
            )

        except Exception as e:
            logger.exception("Failed to mark entry dequeued")
            return JsonResponse({"success": False, "error": str(e)}, status=400)


@method_decorator(user_passes_test(is_officer), name="dispatch")
class LicensePlateRestrictionListView(View):
    def get(self, request):
        active_restrictions = (
            LicensePlateRestriction.objects.filter(active=True)
            .select_related("created_by_officer", "source_queue_entry")
            .order_by("-created_at")
        )

        lifted_restrictions = (
            LicensePlateRestriction.objects.filter(active=False)
            .select_related("created_by_officer", "lifted_by_officer")
            .order_by("-lifted_at", "-created_at")[:100]
        )

        return render(
            request,
            "control_panel/license_plate_restrictions.html",
            {
                "active_restrictions": active_restrictions,
                "lifted_restrictions": lifted_restrictions,
            },
        )

    def post(self, request):
        license_plate = request.POST.get("license_plate", "").strip()
        reason = request.POST.get("reason", "").strip()
        remove_waiting_entries = request.POST.get("remove_waiting_entries") == "on"

        if not license_plate:
            messages.error(request, "Kenteken is verplicht.")
            return redirect("control_panel:license_plate_restrictions")

        try:
            restriction, created, removed_count = block_license_plate(
                license_plate=license_plate,
                officer=request.user.officer,
                reason=reason,
                remove_waiting_entries=remove_waiting_entries,
            )

            if created:
                messages.success(
                    request,
                    f"{restriction.display_license_plate} is geblokkeerd. "
                    f"{removed_count} actieve wachtrij-item(s) verwijderd.",
                )
            else:
                messages.info(
                    request,
                    f"{restriction.display_license_plate} was al geblokkeerd.",
                )

        except Exception as exc:
            logger.exception("Failed to create license plate restriction")
            messages.error(request, f"Kon kenteken niet blokkeren: {exc}")

        return redirect("control_panel:license_plate_restrictions")


@method_decorator(user_passes_test(is_officer), name="dispatch")
class LiftLicensePlateRestrictionView(View):
    def post(self, request, restriction_id):
        restriction = get_object_or_404(
            LicensePlateRestriction,
            id=restriction_id,
            active=True,
        )

        lift_license_plate_restriction(
            restriction=restriction,
            officer=request.user.officer,
        )

        messages.success(
            request,
            f"Blokkade voor {restriction.display_license_plate} is opgeheven.",
        )

        return redirect("control_panel:license_plate_restrictions")


@method_decorator(user_passes_test(is_officer), name="dispatch")
class FlagEntryLicensePlateView(View):
    def post(self, request, queue_id, entry_id):
        queue = get_object_or_404(TaxiQueue, id=queue_id)

        entry = get_object_or_404(
            QueueEntry,
            id=entry_id,
            queue=queue,
        )

        license_plate = (entry.license_plate_snapshot or "").strip()

        if not license_plate:
            return JsonResponse(
                {
                    "success": False,
                    "error": "Geen kenteken gevonden voor deze chauffeur.",
                },
                status=400,
            )

        reason = request.POST.get("reason", "").strip()
        remove_waiting_entries = request.POST.get("remove_waiting_entries") == "1"

        try:
            restriction, created, removed_count = block_license_plate(
                license_plate=license_plate,
                officer=request.user.officer,
                reason=reason,
                source_queue_entry=entry,
                remove_waiting_entries=remove_waiting_entries,
            )

            return JsonResponse(
                {
                    "success": True,
                    "created": created,
                    "removed_count": removed_count,
                    "message": (
                        f"{restriction.display_license_plate} is geblokkeerd. "
                        f"{removed_count} actieve wachtrij-item(s) verwijderd."
                        if created
                        else f"{restriction.display_license_plate} was al geblokkeerd."
                    ),
                }
            )

        except Exception as exc:
            logger.exception("Failed to flag license plate")
            return JsonResponse(
                {
                    "success": False,
                    "error": str(exc),
                },
                status=400,
            )
