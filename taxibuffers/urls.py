"""
URL configuration for taxibuffers project.

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
from queueing.views import service_worker

def redirect_to_signup(request):
    return redirect('queueing:chauffeur_login')

urlpatterns = [
    path("admin/", admin.site.urls),
    path('queueing/', include('queueing.urls')),
    path('', redirect_to_signup, name='home'),
    path('sw.js', service_worker, name='service_worker'),
]
