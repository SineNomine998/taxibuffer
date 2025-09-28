import logging
from django.core.management.base import BaseCommand
from django.utils import timezone as dj_timezone
from django.core.cache import cache

from sensors.models import Sensor, SensorReading
from queueing.services import QueueService
from queueing.models import TaxiQueue

logger = logging.getLogger(__name__)

CACHE_PREFIX = "pickup_zone_free_count_v1"


class Command(BaseCommand):
    help = "Read latest SensorReading per sensor and notify next chauffeurs when free slots appear."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Do not send push notifications; just log actions.",
        )
        parser.add_argument(
            "--pickup-zone-id",
            type=int,
            help="Optionally limit to a single pickup_zone_id",
        )
        parser.add_argument(
            "--serials",
            nargs="+",
            help="Optional list of sensor_id serials to limit polling (for testing)",
        )

    def handle(self, *args, **options):
        dry_run = options.get("dry_run", False)
        pickup_zone_override = options.get("pickup_zone_id")
        serials_filter = options.get("serials")

        # 1) select sensors
        qs = Sensor.objects.filter(active=True).select_related("pickup_zone")
        if pickup_zone_override:
            qs = qs.filter(pickup_zone_id=pickup_zone_override)
        if serials_filter:
            qs = qs.filter(sensor_id__in=serials_filter)

        sensors = list(qs)
        if not sensors:
            self.stdout.write("No active sensors found for the given filters.")
            return

        # 2) group by pickup_zone
        zones = {}
        for s in sensors:
            zones.setdefault(s.pickup_zone_id, []).append(s)

        service = QueueService()

        for zone_id, sensors_in_zone in zones.items():
            # count free sensors by checking latest SensorReading per sensor
            free_count = 0
            for s in sensors_in_zone:
                last = SensorReading.objects.filter(sensor=s).order_by("-date").first()
                if last is None:
                    logger.debug(
                        "Sensor %s has no readings yet; treating as occupied.",
                        s.sensor_id,
                    )
                    # treat as occupied (do not count as free). Change policy here if desired
                    continue
                if last.status is False:  # False = free
                    free_count += 1

            self.stdout.write(
                f"Zone {zone_id}: sensors={len(sensors_in_zone)}, free_count={free_count}"
            )

            # find TaxiQueue(s) for this pickup zone
            queues = TaxiQueue.objects.filter(pickup_zone_id=zone_id, active=True)
            if not queues.exists():
                logger.debug("No TaxiQueue found for pickup_zone %s; skipping", zone_id)
                continue

            cache_key = f"{CACHE_PREFIX}:{zone_id}"
            cached = cache.get(cache_key)  # expected format: {"free": int, "ts": "iso"}
            last_free = cached.get("free") if cached else None

            # TODO: Should we only notify if free_count changed?
            if last_free is None or free_count != last_free:
                self.stdout.write(
                    f"Free count changed for zone {zone_id}: Last free ({last_free}) -> {free_count}"
                )
                # Notify: notify up to free_count chauffeurs across queues (spread fairly)
                remaining = free_count
                total_notified = 0
                for q in queues:
                    if remaining <= 0:
                        break
                    try:
                        if dry_run:
                            # call with send_push=False so we simulate but still let queue entries move if the service updates them
                            notified = service.notify_next_chauffeurs(
                                q, remaining, {"send_push": False}
                            )
                            logger.info(
                                "[dry-run] notify_next_chauffeurs called for queue %s with %s",
                                q.id,
                                remaining,
                            )
                        else:
                            notified = service.notify_next_chauffeurs(
                                q, remaining, {"send_push": True}
                            )
                            logger.info(
                                "notify_next_chauffeurs called for queue %s with %s",
                                q.id,
                                remaining,
                            )

                        if isinstance(notified, int):
                            total_notified += notified
                            remaining -= notified
                        else:
                            # if the service returns something else, we just log it
                            logger.info(
                                "notify_next_chauffeurs returned %s for queue %s",
                                type(notified),
                                q.id,
                            )
                    except Exception as e:
                        logger.exception("Failed to notify queue %s: %s", q.id, e)

                cache.set(
                    cache_key,
                    {"free": free_count, "ts": dj_timezone.now().isoformat()},
                    timeout=None,
                )
                self.stdout.write(
                    f"Zone {zone_id}: notified={total_notified} (requested free={free_count})"
                )
            else:
                self.stdout.write(
                    f"Zone {zone_id}: free count unchanged ({free_count}) - no notifications sent."
                )
