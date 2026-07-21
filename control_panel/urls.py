from django.urls import path
from . import views

app_name = "control_panel"

urlpatterns = [
    path("login/", views.OfficerLoginView.as_view(), name="login"),
    path("logout/", views.OfficerLogoutView.as_view(), name="logout"),
    path("", views.OfficerDashboardView.as_view(), name="dashboard"),
    path(
        "queue/<int:queue_id>/", views.QueueMonitorView.as_view(), name="queue_monitor"
    ),
    path(
        "api/queue/<int:queue_id>/status/",
        views.QueueStatusAPIView.as_view(),
        name="queue_status_api",
    ),
    path(
        "queue/<int:queue_id>/busje/",
        views.BypassBusjeView.as_view(),
        name="busje_management",
    ),
    path(
        "queue/<int:queue_id>/voertuig/",
        views.BypassVehicleView.as_view(),
        name="vehicle_management",
    ),
    path(
        "queue/<int:queue_id>/entry/<int:entry_id>/dequeue/",
        views.MarkEntryDequeuedView.as_view(),
        name="mark_entry_dequeued",
    ),
    path(
        "queue/<int:queue_id>/toggle-pause/",
        views.PauseQueueView.as_view(),
        name="toggle_queue_pause",
    ),
    path(
        "queue/<int:queue_id>/toggle-activation/",
        views.ToggleQueueActivationView.as_view(),
        name="toggle_queue_activation",
    ),
    # Punishment endpoints
    path(
        "punishments/",
        views.LicensePlateRestrictionListView.as_view(),
        name="license_plate_restrictions",
    ),
    path(
        "punishments/<int:restriction_id>/lift/",
        views.LiftLicensePlateRestrictionView.as_view(),
        name="lift_license_plate_restriction",
    ),
    path(
        "queue/<int:queue_id>/entry/<int:entry_id>/flag-license-plate/",
        views.FlagEntryLicensePlateView.as_view(),
        name="flag_entry_license_plate",
    ),
    # Queue history endpoints (for dequeued chauffeurs)
    path(
        "queue/<int:queue_id>/history/",
        views.QueueHistoryView.as_view(),
        name="queue_history",
    ),
]
