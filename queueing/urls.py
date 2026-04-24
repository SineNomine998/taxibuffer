from django.urls import path, reverse_lazy
from . import views
from . import push_views

app_name = "queueing"

urlpatterns = [
    # Two-step chauffeur authentication and queue joining
    path("", views.InfoPagesView.as_view(), name="info_pages"),
    path("login/", views.ChauffeurLoginView.as_view(), name="chauffeur_login"),
    path(
        "locations/", views.LocationSelectionView.as_view(), name="location_selection"
    ),
    path("locations/info/", views.LocationSelectionInfoView.as_view(), name="location_selection_info"),
    # Queue status and management
    path(
        "queue/<uuid:entry_uuid>/", views.QueueStatusView.as_view(), name="queue_status"
    ),
    path("queue/", views.QueueOverviewView.as_view(), name="queue_overview"),
    # API endpoints
    path(
        "api/queue/<uuid:entry_uuid>/status/",
        views.QueueStatusAPIView.as_view(),
        name="queue_status_api",
    ),
    path(
        "api/notification/respond/",
        views.NotificationResponseView.as_view(),
        name="notification_response",
    ),
    path(
        "api/queue/<uuid:entry_uuid>/leave/",
        views.LeaveQueueBeforeNotificationAPIView.as_view(),
        name="leave_queue",
    ),
    # Testing/Admin views
    path(
        "admin/queue/<int:queue_id>/trigger/",
        views.ManualTriggerView.as_view(),
        name="manual_trigger",
    ),
    # Signup and account management
    path("signup/", views.SignUpStep1View.as_view(), name="signup"),
    path("signup/step-1/", views.SignUpStep1View.as_view(), name="sign_up1"),
    path("signup/step-2/", views.SignUpPasswordView.as_view(), name="sign_up2"),
    path("signup/step-3/", views.SignUpVehicleView.as_view(), name="sign_up3"),
    path(
        "signup/vehicle/add/",
        views.SignUpAddVehicleView.as_view(),
        name="sign_up_vehicle_add",
    ),
    # Password reset views
    path(
        "password-reset/",
        views.PasswordResetView.as_view(
            template_name="queueing/password_reset_form.html",
            email_template_name="queueing/password_reset_email.html",
            subject_template_name="queueing/password_reset_subject.txt",
            success_url=reverse_lazy("queueing:password_reset_done"),
        ),
        name="password_reset",
    ),
    path(
        "password-reset/done/",
        views.PasswordResetDoneView.as_view(
            template_name="queueing/password_reset_done.html"
        ),
        name="password_reset_done",
    ),
    path(
        "password-reset-confirm/<uidb64>/<token>/",
        views.PasswordResetConfirmView.as_view(),
        name="password_reset_confirm",
    ),
    path(
        "password-reset-complete/",
        views.PasswordResetCompleteView.as_view(
            template_name="queueing/password_reset_complete.html"
        ),
        name="password_reset_complete",
    ),
    path(
        "password-change/",
        views.PasswordChangeView.as_view(),
        name="password_change",
    ),
    path(
        "password-change/done/",
        views.PasswordChangeDoneView.as_view(),
        name="password_change_done",
    ),
    # Account management
    path("account/", views.AccountView.as_view(), name="account"),
    path("logout/", views.ChauffeurLogoutView.as_view(), name="chauffeur_logout"),
    # Sequence history for chauffeurs
    path("sequence-history/", views.SequenceHistoryView.as_view(), name="sequence_history"),
    # Push notification subscription
    path("api/push/subscribe/", push_views.push_subscribe, name="push_subscribe"),
    path("api/push/test/", push_views.test_push, name="push_test"),
]
