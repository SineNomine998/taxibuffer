from django.contrib.auth.backends import ModelBackend
from .models import User

class EmailBackend(ModelBackend):
    def authenticate(self, request, username=None, password=None, **kwargs):
        email = kwargs.get("email") or username
        if not email or not password:
            return None

        try:
            user = User.objects.get(email__iexact=email, is_chauffeur=True)
        except User.DoesNotExist:
            return None

        return user if user.check_password(password) else None
