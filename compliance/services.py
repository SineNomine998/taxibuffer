from django.utils import timezone

from compliance.models import (
    PrivacyPolicy,
    PrivacyPolicyAcceptance,
    TermsOfUse,
    TermsOfUseAcceptance,
)


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


def get_active_terms_of_use():
    return (
        TermsOfUse.objects.filter(is_active=True, effective_from__lte=timezone.now())
        .order_by("-effective_from")
        .first()
    )


def has_accepted_active_terms_of_use(chauffeur):
    terms = get_active_terms_of_use()

    if terms is None:
        return True

    return TermsOfUseAcceptance.objects.filter(
        chauffeur=chauffeur,
        terms=terms,
    ).exists()


def accept_active_terms_of_use(*, chauffeur, request):
    terms = get_active_terms_of_use()

    if terms is None:
        return None

    acceptance, _ = TermsOfUseAcceptance.objects.get_or_create(
        chauffeur=chauffeur,
        terms=terms,
        defaults={
            "user_agent": request.META.get("HTTP_USER_AGENT", "")[:2000],
        },
    )

    return acceptance
