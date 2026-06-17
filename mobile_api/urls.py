from django.urls import path
from . import views

app_name = "mobile_api"

urlpatterns = [
    path("auth/login/", views.MobileLoginView.as_view(), name="mobile_login"),
    path("auth/refresh/", views.MobileTokenRefreshView.as_view(), name="mobile_token_refresh"),
    path("auth/logout/", views.MobileLogoutView.as_view(), name="mobile_logout"),
    path("me/", views.MobileMeView.as_view(), name="mobile_me"),
]
