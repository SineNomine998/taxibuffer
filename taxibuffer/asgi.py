"""
ASGI config for taxibuffer project.

It exposes the ASGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/5.2/howto/deployment/asgi/
"""

import os
from django.core.asgi import get_asgi_application
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from mobile_api.middleware import JwtAuthMiddleware
import mobile_api.routing

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "taxibuffer.settings")

application = ProtocolTypeRouter(
    {
        "http": get_asgi_application(),
        "websocket": JwtAuthMiddleware(
            URLRouter(mobile_api.routing.websocket_urlpatterns)
        ),
    }
)
