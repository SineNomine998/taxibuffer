from django.urls import path
from . import views

app_name = "mobile_api"

urlpatterns = [
    # Privacy endpoints
    path("bootstrap/", views.MobileBootstrapView.as_view(), name="mobile_bootstrap"),
    path(
        "privacy-policy/public/",
        views.PublicPrivacyPolicyView.as_view(),
        name="mobile_public_privacy_policy",
    ),
    path(
        "privacy-policy/",
        views.MobilePrivacyPolicyView.as_view(),
        name="mobile_privacy_policy",
    ),
    path(
        "privacy-policy/accept/",
        views.MobileAcceptPrivacyPolicyView.as_view(),
        name="mobile_accept_privacy_policy",
    ),
    # Login endpoints
    path("auth/login/", views.MobileLoginView.as_view(), name="mobile_login"),
    path(
        "auth/refresh/",
        views.MobileTokenRefreshView.as_view(),
        name="mobile_token_refresh",
    ),
    path("auth/logout/", views.MobileLogoutView.as_view(), name="mobile_logout"),
    # Sign-up endpoints
    path("auth/signup/", views.MobileSignUpView.as_view(), name="mobile_signup"),
    path(
        "auth/check-email/",
        views.MobileCheckEmailView.as_view(),
        name="mobile_email_check",
    ),
    # Password reset endpoints
    path(
        "auth/password-reset/",
        views.MobilePasswordResetView.as_view(),
        name="mobile_password_reset",
    ),
    # Account endpoints
    path("account/", views.MobileAccountView.as_view(), name="mobile_account"),
    path(
        "account/profile/",
        views.MobileAccountProfileView.as_view(),
        name="mobile_account_profile",
    ),
    path(
        "account/vehicles/",
        views.MobileVehicleCreateView.as_view(),
        name="mobile_vehicle_create",
    ),
    path(
        "account/vehicles/<int:vehicle_id>/set-current/",
        views.MobileVehicleSetCurrentView.as_view(),
        name="mobile_vehicle_set_current",
    ),
    path(
        "account/vehicles/<int:vehicle_id>/",
        views.MobileVehicleDetailView.as_view(),
        name="mobile_vehicle_delete_and_adjust",
    ),
    # Queue endpoints
    path("queues/", views.MobileQueueListView.as_view(), name="mobile_queue_list"),
    path(
        "queues/<int:queue_id>/validate-location/",
        views.MobileValidateLocationView.as_view(),
        name="mobile_validate_location",
    ),
    path(
        "queues/<int:queue_id>/join/",
        views.MobileJoinQueueView.as_view(),
        name="mobile_join_queue",
    ),
    path(
        "queue/status/",
        views.MobileQueueStatusView.as_view(),
        name="mobile_queue_status",
    ),
    path(
        "queue/leave/",
        views.MobileLeaveQueueView.as_view(),
        name="mobile_leave_queue",
    ),
    path(
        "queue/<uuid:entry_uuid>/location-report/",
        views.MobileQueueLocationReportView.as_view(),
        name="mobile_queue_location_report",
    ),
    # Notification endpoints
    path(
        "notifications/respond/",
        views.MobileNotificationResponseView.as_view(),
        name="mobile_notification_response",
    ),
    path("push-token/", views.MobilePushTokenView.as_view(), name="mobile_push_token"),
    # Sequence history endpoints
    path(
        "sequence-history/",
        views.MobileSequenceHistoryView.as_view(),
        name="mobile_sequence_history",
    ),
    # User activity endpoints
    path(
        "activity/",
        views.MobileActivityLogView.as_view(),
        name="mobile_activity",
    ),
]
