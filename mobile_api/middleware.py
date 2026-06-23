from urllib.parse import parse_qs
from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from django.contrib.auth import get_user_model
from rest_framework_simplejwt.tokens import AccessToken

User = get_user_model()


@database_sync_to_async
def get_user_from_token(token_str):
    try:
        token = AccessToken(token_str)
        user_id = token["user_id"]
        print("WS token user_id:", user_id)

        user = User.objects.get(id=user_id)
        print("WS resolved user:", user, "is_active:", user.is_active)

        return user
    except Exception as e:
        print("WS token auth failed:", repr(e))
        return AnonymousUser()


class JwtAuthMiddleware:
    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        query_string = scope.get("query_string", b"").decode()
        params = parse_qs(query_string)

        token = params.get("token", [""])[0]

        scope["user"] = await get_user_from_token(token)

        print("WS query string:", query_string)
        print("WS token exists:", bool(token))
        print("WS user:", scope["user"])

        return await self.inner(scope, receive, send)
