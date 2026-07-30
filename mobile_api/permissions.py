from rest_framework.permissions import BasePermission

from mobile_api.utils import get_current_chauffeur, chauffeur_profile_complete


class HasCompletedRequiredProfile(BasePermission):
    message = "Vul eerst uw TTO en telefoonnummer in."

    def has_permission(self, request, view):
        chauffeur = get_current_chauffeur(request.user)

        if chauffeur is None:
            return False

        return bool(
            chauffeur.tto
            and chauffeur.tto.strip()
            and chauffeur.phone_number
            and chauffeur.phone_number.strip()
        )
