from django.urls import path
from .views import sensor_data

urlpatterns = [
    path("api/v1/sensor-data/", sensor_data, name="sensor_data"),
]
