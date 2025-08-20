# queueing/urls.py
from django.urls import path
from . import views

app_name = 'queueing'

urlpatterns = [
    # Chauffeur views
    path('signup/', views.ChauffeurSignupView.as_view(), name='signup'),
    path('queue/<int:queue_id>/chauffeur/<int:chauffeur_id>/', 
         views.QueueStatusView.as_view(), name='queue_status'),
    
    # API endpoints
    path('api/queue/<int:queue_id>/chauffeur/<int:chauffeur_id>/status/', 
         views.QueueStatusAPIView.as_view(), name='queue_status_api'),
    path('api/notification/respond/', 
         views.NotificationResponseView.as_view(), name='notification_response'),
    
    # Testing/Admin views
    path('queue/<int:queue_id>/trigger/', 
         views.ManualTriggerView.as_view(), name='manual_trigger'),
]
