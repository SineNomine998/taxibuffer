from django.urls import path
from . import views

app_name = "control_panel"

urlpatterns = [
    path("login/", views.OfficerLoginView.as_view(), name="login"),
    path("logout/", views.OfficerLogoutView.as_view(), name="logout"),
    path("", views.OfficerDashboardView.as_view(), name="dashboard"),
    path("queue/<int:queue_id>/", views.QueueMonitorView.as_view(), name="queue_monitor"),
    path("api/queue/<int:queue_id>/status/", views.QueueStatusAPIView.as_view(), name="queue_status_api"),
]