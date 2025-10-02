from django.urls import path
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
    # Queue status and management
    path(
        "queue/<uuid:entry_uuid>/", views.QueueStatusView.as_view(), name="queue_status"
    ),
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
    path(
        "ajax/set-vehicle-type/",
        views.SetVehicleTypeView.as_view(),
        name="set_vehicle_type",
    ),
    # Testing/Admin views
    path(
        "admin/queue/<int:queue_id>/trigger/",
        views.ManualTriggerView.as_view(),
        name="manual_trigger",
    ),
    path("signup/", views.ChauffeurLoginView.as_view(), name="signup"),
    # Push notification subscription
    path("api/push/subscribe/", push_views.push_subscribe, name="push_subscribe"),
    path("api/push/test/", push_views.test_push, name="push_test"),
]
