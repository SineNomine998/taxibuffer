import json
import asyncio
from django.utils import timezone
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser

from queueing.models import QueueEntry, QueueNotification
from queueing.constants import ACTIVE_QUEUE_STATUSES
from .serializers import serialize_waiting_entry


class QueueStatusConsumer(AsyncWebsocketConsumer):
    POLL_INTERVAL = 10  # seconds

    async def connect(self):
        user = self.scope.get("user")

        print("WS connect user:", self.scope.get("user"))
        print("WS authenticated:", self.scope.get("user").is_authenticated)

        if not user or not user.is_authenticated:
            await self.close(code=4001)
            return

        self.entry_uuid = self.scope["url_route"]["kwargs"]["entry_uuid"]
        self.running = True
        await self.accept()
        asyncio.ensure_future(self._push_loop())

    async def disconnect(self, close_code):
        self.running = False

    async def receive(self, text_data=None, bytes_data=None):
        # Client can send {"action": "leave"} to dequeue
        if not text_data:
            return
        data = json.loads(text_data)
        if data.get("action") == "leave":
            success = await self._leave_queue()
            await self.send(
                json.dumps(
                    {
                        "type": "leave_result",
                        "success": success,
                    }
                )
            )

    async def _push_loop(self):
        while self.running:
            try:
                payload = await self._build_status_payload()
                await self.send(json.dumps(payload, default=str))
            except Exception as e:
                await self.send(json.dumps({"type": "error", "detail": str(e)}))
            await asyncio.sleep(self.POLL_INTERVAL)

    @database_sync_to_async
    def _build_status_payload(self):
        try:
            entry = QueueEntry.objects.select_related(
                "chauffeur__user",
                "queue__pickup_zone",
                "queue__buffer_zone",
            ).get(uuid=self.entry_uuid, status__in=ACTIVE_QUEUE_STATUSES)
        except QueueEntry.DoesNotExist:
            return {"type": "status", "active": False}

        chauffeur = entry.chauffeur
        queue = entry.queue
        position = entry.get_queue_position()

        waiting_entries = (
            queue.get_waiting_entries()
            .select_related("chauffeur__user")
            .order_by("created_at")
        )
        waiting_people = [
            serialize_waiting_entry(e, chauffeur.id) for e in waiting_entries
        ]

        # Check for unacknowledged notification
        notification = (
            QueueNotification.objects.filter(queue_entry=entry, response__isnull=True)
            .order_by("-notification_time")
            .first()
        )

        from .serializers import serialize_notification

        pickup_zone = queue.pickup_zone

        return {
            "type": "status",
            "active": True,
            "position": position,
            "queue_name": getattr(pickup_zone, "name", str(queue)),
            "queue_address": getattr(pickup_zone, "address", None),
            "image_url": getattr(pickup_zone, "image_url", None),
            "waiting_people": waiting_people,
            "notification": serialize_notification(notification),
            "has_notification": notification is not None,
        }

    @database_sync_to_async
    def _leave_queue(self):
        try:
            entry = QueueEntry.objects.get(
                uuid=self.entry_uuid,
                status__in=ACTIVE_QUEUE_STATUSES,
                chauffeur__user=self.scope["user"],
            )
            entry.status = QueueEntry.Status.LEFT_ZONE
            entry.dequeued_at = timezone.now()
            entry.save()
            return True
        except QueueEntry.DoesNotExist:
            return False
