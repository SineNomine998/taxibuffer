from django.contrib import admin

from compliance.models import (
    PrivacyPolicy,
    PrivacyPolicyAcceptance,
    TermsOfUse,
    TermsOfUseAcceptance,
)


@admin.register(PrivacyPolicy)
class PrivacyPolicyAdmin(admin.ModelAdmin):
    list_display = ("version", "title", "effective_from", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("version", "title", "body_nl")


@admin.register(PrivacyPolicyAcceptance)
class PrivacyPolicyAcceptanceAdmin(admin.ModelAdmin):
    list_display = ("chauffeur", "policy", "accepted_at")
    list_filter = ("policy", "accepted_at")
    search_fields = (
        "chauffeur__user__email",
        "chauffeur__user__username",
        "policy__version",
    )
    readonly_fields = (
        "chauffeur",
        "policy",
        "accepted_at",
        "user_agent",
    )


@admin.register(TermsOfUse)
class TermsOfUseAdmin(admin.ModelAdmin):
    list_display = ("version", "title", "effective_from", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("version", "title", "body_nl")


@admin.register(TermsOfUseAcceptance)
class TermsOfUseAcceptanceAdmin(admin.ModelAdmin):
    list_display = ("chauffeur", "terms", "accepted_at")
    list_filter = ("terms", "accepted_at")
    search_fields = (
        "chauffeur__user__email",
        "chauffeur__user__username",
        "terms__version",
    )
    readonly_fields = (
        "chauffeur",
        "terms",
        "accepted_at",
        "user_agent",
    )
