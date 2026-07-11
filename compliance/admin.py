from django.contrib import admin

from compliance.models import PrivacyPolicy, PrivacyPolicyAcceptance


@admin.register(PrivacyPolicy)
class PrivacyPolicyAdmin(admin.ModelAdmin):
    list_display = ("version", "title", "effective_from", "is_active", "created_at")
    list_filter = ("is_active",)
    search_fields = ("version", "title", "body_nl")


@admin.register(PrivacyPolicyAcceptance)
class PrivacyPolicyAcceptanceAdmin(admin.ModelAdmin):
    list_display = ("chauffeur", "policy", "accepted_at", "accepted_ip")
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
        "accepted_ip",
        "user_agent",
    )
