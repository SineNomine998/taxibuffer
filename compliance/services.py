from django.utils import timezone

from compliance.models import PrivacyPolicy, PrivacyPolicyAcceptance


def get_active_privacy_policy():
    return (
        PrivacyPolicy.objects.filter(
            is_active=True,
            effective_from__lte=timezone.now(),
        )
        .order_by("-effective_from", "-created_at")
        .first()
    )


def has_accepted_active_privacy_policy(chauffeur):
    policy = get_active_privacy_policy()

    if policy is None:
        # Production safety choice:
        # If no policy is configured, do NOT block the app accidentally.
        # But log this in production monitoring.
        return True

    return PrivacyPolicyAcceptance.objects.filter(
        chauffeur=chauffeur,
        policy=policy,
    ).exists()


def accept_active_privacy_policy(*, chauffeur, request):
    policy = get_active_privacy_policy()

    if policy is None:
        raise ValueError("No active privacy policy configured.")

    acceptance, _ = PrivacyPolicyAcceptance.objects.get_or_create(
        chauffeur=chauffeur,
        policy=policy,
        defaults={
            "user_agent": request.META.get("HTTP_USER_AGENT", "")[:2000],
        },
    )

    return acceptance
