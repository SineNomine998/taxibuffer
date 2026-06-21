from django.urls import path
from . import views

app_name = "mobile_api"

urlpatterns = [
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
        views.MobileVehicleDeleteView.as_view(),
        name="mobile_vehicle_delete",
    ),
]
