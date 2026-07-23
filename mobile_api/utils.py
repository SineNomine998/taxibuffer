from rest_framework.exceptions import PermissionDenied


def get_current_chauffeur(user):
    chauffeur = getattr(user, "chauffeur", None)
    if chauffeur is None:
        raise PermissionDenied("Geen chauffeurprofiel gevonden.")
    return chauffeur


def chauffeur_profile_complete(chauffeur):
    return bool(
        chauffeur.tto
        and chauffeur.tto.strip()
        and chauffeur.phone_number
        and chauffeur.phone_number.strip()
    )
