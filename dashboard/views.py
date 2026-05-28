from collections import Counter
from datetime import datetime, timedelta
from operator import itemgetter
import json

import pytz
from django.db.models import Count, Q
from django.db.models.functions import TruncDate
from django.shortcuts import render
from django.utils import timezone
from django.views import View

from queueing.models import QueueEntry, TaxiQueue


class DashboardView(View):
    def get(self, request):
        europe = pytz.timezone("Europe/Amsterdam")

        selected_day = request.GET.get("selected_day", "all")
        selected_queue = request.GET.get("selected_queue", "all")

        # -------------------------
        # Day dropdown
        # -------------------------
        day_choices = (
            QueueEntry.objects.annotate(day=TruncDate("created_at", tzinfo=europe))
            .values("day")
            .annotate(enqueued_count=Count("id"))
            .order_by("-day")
        )

        day_options = [{"value": "all", "label": "All time combined"}]

        for item in day_choices:
            if item["day"]:
                day_options.append(
                    {
                        "value": item["day"].isoformat(),
                        "label": item["day"].strftime("%b %d, %Y"),
                    }
                )

        # -------------------------
        # Queue dropdown
        # -------------------------
        queue_options = [{"value": "all", "label": "All queues"}]

        queues = TaxiQueue.objects.all().order_by("name")

        for queue in queues:
            queue_options.append(
                {
                    "value": str(queue.id),
                    "label": queue.name,
                }
            )

        selected_day_label = "All time combined"

        start_utc = None
        end_utc = None

        if selected_day != "all":
            try:
                day_date = datetime.fromisoformat(selected_day).date()

                selected_day_label = day_date.strftime("%b %d, %Y")

                local_period_start = europe.localize(
                    datetime(
                        day_date.year,
                        day_date.month,
                        day_date.day,
                        0,
                        0,
                        0,
                    )
                )

                local_period_end = local_period_start + timedelta(days=1)

                start_utc = local_period_start.astimezone(pytz.UTC)
                end_utc = local_period_end.astimezone(pytz.UTC)

            except ValueError:
                selected_day = "all"
                selected_day_label = "All time combined"

        # -------------------------
        # Hour labels
        # -------------------------
        labels = [f"{hour:02d}:00" for hour in range(24)]

        # -------------------------
        # Base querysets
        # -------------------------
        enqueued_qs = QueueEntry.objects.all()
        notified_qs = QueueEntry.objects.filter(notified_at__isnull=False)

        # -------------------------
        # Queue filter
        # -------------------------
        if selected_queue != "all":
            enqueued_qs = enqueued_qs.filter(queue_id=selected_queue)
            notified_qs = notified_qs.filter(queue_id=selected_queue)

        # -------------------------
        # Day filter
        # -------------------------
        if selected_day != "all" and start_utc and end_utc:
            enqueued_qs = enqueued_qs.filter(
                created_at__gte=start_utc,
                created_at__lt=end_utc,
            )

            notified_qs = notified_qs.filter(
                notified_at__gte=start_utc,
                notified_at__lt=end_utc,
            )

        enqueued_dates = enqueued_qs.values_list("created_at", flat=True)
        notified_dates = notified_qs.values_list("notified_at", flat=True)

        # -------------------------
        # Build hourly counts
        # -------------------------
        def build_counts(dates):
            counter = Counter()

            for dt in dates:
                if dt is None:
                    continue

                local = dt.astimezone(europe)

                hour_key = local.hour

                counter[hour_key] += 1

            return [counter.get(hour, 0) for hour in range(24)]

        enqueued_counts = build_counts(enqueued_dates)
        notified_counts = build_counts(notified_dates)

        busiest_enqueued = max(
            zip(labels, enqueued_counts),
            key=itemgetter(1),
            default=(None, 0),
        )

        busiest_notified = max(
            zip(labels, notified_counts),
            key=itemgetter(1),
            default=(None, 0),
        )

        # -------------------------
        # Status distribution
        # -------------------------
        status_map = {choice.value: choice.label for choice in QueueEntry.Status}

        status_counts_qs = enqueued_qs.values("status").annotate(count=Count("id"))

        status_counts = [
            {
                "status": status_map.get(item["status"], item["status"]),
                "count": item["count"],
            }
            for item in status_counts_qs
        ]

        # -------------------------
        # Queue statistics
        # -------------------------
        queue_stats = (
            TaxiQueue.objects.values("id", "name")
            .annotate(
                waiting_count=Count(
                    "queueentry",
                    filter=Q(queueentry__status=QueueEntry.Status.WAITING),
                ),
                notified_count=Count(
                    "queueentry",
                    filter=Q(queueentry__status=QueueEntry.Status.NOTIFIED),
                ),
                total_count=Count("queueentry"),
            )
            .order_by("-waiting_count", "-notified_count")
        )

        top_queues = [
            {
                "name": queue["name"],
                "waiting_count": queue["waiting_count"],
                "notified_count": queue["notified_count"],
                "total_count": queue["total_count"],
            }
            for queue in queue_stats[:6]
        ]

        total_waiting = enqueued_qs.filter(status=QueueEntry.Status.WAITING).count()

        total_notified = notified_qs.count()
        total_enqueued = enqueued_qs.count()

        context = {
            "labels": labels,
            "enqueued_counts": enqueued_counts,
            "notified_counts": notified_counts,
            "status_counts": status_counts,
            "queue_stats": queue_stats,
            "labels_json": json.dumps(labels),
            "enqueued_counts_json": json.dumps(enqueued_counts),
            "notified_counts_json": json.dumps(notified_counts),
            "status_counts_json": json.dumps(status_counts),
            "queue_stats_json": json.dumps(list(queue_stats)),
            "top_queues": top_queues,
            "total_waiting": total_waiting,
            "total_notified": total_notified,
            "total_enqueued": total_enqueued,
            "busiest_enqueued": busiest_enqueued,
            "busiest_notified": busiest_notified,
            "selected_day": selected_day,
            "selected_day_label": selected_day_label,
            "day_options": day_options,
            "selected_queue": selected_queue,
            "queue_options": queue_options,
        }

        return render(
            request,
            "dashboard/dashboard.html",
            context,
        )
