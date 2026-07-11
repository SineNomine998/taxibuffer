from rest_framework.permissions import BasePermission

from compliance.services import has_accepted_active_privacy_policy


class HasAcceptedPrivacyPolicy(BasePermission):
    message = "Privacyverklaring moet eerst worden geaccepteerd."

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False

        chauffeur = getattr(request.user, "chauffeur", None)

        if chauffeur is None:
            return False

        return has_accepted_active_privacy_policy(chauffeur)
