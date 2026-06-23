from django.urls import path
from . import consumers

websocket_urlpatterns = [
    path("ws/queue/<str:entry_uuid>/", consumers.QueueStatusConsumer.as_asgi()),
]
