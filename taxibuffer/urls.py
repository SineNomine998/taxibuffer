"""
URL configuration for taxibuffer project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""

from django.contrib import admin
from django.urls import path, include
from django.shortcuts import redirect
from queueing.views import service_worker, InfoPagesView
from django.conf import settings
from django.conf.urls.static import static
from compliance import views as compliance_views


def redirect_to_signup(request):
    return redirect("queueing:chauffeur_login")


urlpatterns = [
    path("admin/", admin.site.urls),
    path("queueing/", include("queueing.urls")),
    path("control/", include("control_panel.urls")),
    path("dashboard/", include("dashboard.urls")),
    path("geofence/", include("geofence.urls")),
    path("", InfoPagesView.as_view(), name="info_pages"),
    path("sw.js", service_worker, name="service_worker"),
    path("", include("sensors.urls")),
    path("api/mobile/", include("mobile_api.urls")),
    path(
        "privacy/", compliance_views.public_privacy_policy, name="public_privacy_policy"
    ),
    path("terms/", compliance_views.public_terms_of_use, name="public_terms_of_use"),
    path(
        "account-verwijderen/",
        compliance_views.public_account_deletion,
        name="public_account_deletion",
    ),
]

if settings.DEBUG:
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
