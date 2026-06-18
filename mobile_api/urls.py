from django.urls import path
from . import views

app_name = "mobile_api"

urlpatterns = [
    # Login endpoints
    path("auth/login/", views.MobileLoginView.as_view(), name="mobile_login"),
    path("auth/refresh/", views.MobileTokenRefreshView.as_view(), name="mobile_token_refresh"),
    path("auth/logout/", views.MobileLogoutView.as_view(), name="mobile_logout"),
    
    # Info about the user (may not be necessary)
    path("me/", views.MobileMeView.as_view(), name="mobile_me"),

    # Sign-up endpoints
    path("auth/signup/", views.MobileSignUpView.as_view(), name="mobile_signup"),
]
