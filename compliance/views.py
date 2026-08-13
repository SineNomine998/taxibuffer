from django.shortcuts import render
from django.utils import timezone

from compliance.models import PrivacyPolicy, TermsOfUse


def public_privacy_policy(request):
    policy = (
        PrivacyPolicy.objects.filter(
            is_active=True,
            effective_from__lte=timezone.now(),
        )
        .order_by("-effective_from", "-created_at")
        .first()
    )

    return render(
        request,
        "compliance/privacy_policy_public.html",
        {"policy": policy},
    )


def public_terms_of_use(request):
    terms = (
        TermsOfUse.objects.filter(
            is_active=True,
            effective_from__lte=timezone.now(),
        )
        .order_by("-effective_from", "-created_at")
        .first()
    )

    return render(
        request,
        "compliance/terms_of_use_public.html",
        {"terms": terms},
    )
