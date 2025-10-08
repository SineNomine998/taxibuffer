from django.urls import path
from .views import ValidateLocationView
app_name = "geofence"

urlpatterns = [
    path('validate-location/', ValidateLocationView.as_view(), name='validate_location'),
]