from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from django.views import View
from django.contrib.gis.geos import Point
from django.utils import timezone
from django.db import transaction
import json

from accounts.models import Chauffeur, User
from geofence.models import BufferZone, PickupZone
from .models import TaxiQueue, QueueEntry, QueueNotification
from .services import QueueService


class ChauffeurSignupView(View):
    """Handle chauffeur signup and queue joining."""
    
    def get(self, request):
        """Display signup form."""
        # Get available queues for selection
        active_queues = TaxiQueue.objects.filter(active=True).select_related(
            'buffer_zone', 'pickup_zone'
        )
        
        context = {
            'queues': active_queues,
        }
        return render(request, 'queueing/signup.html', context)
    
    def post(self, request):
        """Process signup form."""
        license_plate = request.POST.get('license_plate', '').strip().upper()
        taxi_license_number = request.POST.get('taxi_license_number', '').strip()
        queue_id = request.POST.get('queue_id')
        
        # Basic validation
        if not all([license_plate, taxi_license_number, queue_id]):
            messages.error(request, 'All fields are required.')
            return redirect('queueing:signup')
        
        try:
            queue = TaxiQueue.objects.get(id=queue_id, active=True)
        except TaxiQueue.DoesNotExist:
            messages.error(request, 'Invalid queue selected.')
            return redirect('queueing:signup')
        
        # Mock location (you can replace this with actual location later)
        mock_location = Point(-74.0059, 40.7128)  # NYC coordinates as example
        
        try:
            with transaction.atomic():
                # Check if chauffeur already exists
                try:
                    chauffeur = Chauffeur.objects.get(license_plate=license_plate)
                    # Verify taxi license matches
                    if chauffeur.taxi_license_number != taxi_license_number:
                        messages.error(request, 'License plate and taxi license number do not match.')
                        return redirect('queueing:signup')
                except Chauffeur.DoesNotExist:
                    # Create new user and chauffeur
                    user = User.objects.create_user(
                        username=f"chauffeur_{license_plate.lower()}",
                        is_chauffeur=True
                    )
                    chauffeur = Chauffeur.objects.create(
                        user=user,
                        license_plate=license_plate,
                        taxi_license_number=taxi_license_number,
                        location=mock_location
                    )
                
                # Use QueueService to add chauffeur to queue
                queue_service = QueueService()
                success, message = queue_service.add_chauffeur_to_queue(
                    chauffeur=chauffeur,
                    queue=queue,
                    signup_location=mock_location
                )
                
                if success:
                    messages.success(request, message)
                    return redirect('queueing:queue_status', queue_id=queue.id, chauffeur_id=chauffeur.id)
                else:
                    messages.error(request, message)
                    return redirect('queueing:signup')
                    
        except Exception as e:
            messages.error(request, f'An error occurred: {str(e)}')
            return redirect('queueing:signup')


class QueueStatusView(View):
    """Display queue status for a specific chauffeur."""
    
    def get(self, request, queue_id, chauffeur_id):
        """Display queue status page."""
        try:
            queue = TaxiQueue.objects.get(id=queue_id, active=True)
            chauffeur = Chauffeur.objects.get(id=chauffeur_id)
            
            # Get chauffeur's queue entry
            try:
                entry = QueueEntry.objects.get(queue=queue, chauffeur=chauffeur)
            except QueueEntry.DoesNotExist:
                messages.error(request, 'You are not in this queue.')
                return redirect('queueing:signup')
            
            context = {
                'queue': queue,
                'chauffeur': chauffeur,
                'entry': entry,
            }
            return render(request, 'queueing/queue_status.html', context)
            
        except (TaxiQueue.DoesNotExist, Chauffeur.DoesNotExist):
            messages.error(request, 'Invalid queue or chauffeur.')
            return redirect('queueing:signup')


class QueueStatusAPIView(View):
    """API endpoint for live queue status updates."""
    
    def get(self, request, queue_id, chauffeur_id):
        """Return JSON with current queue status."""
        try:
            queue = TaxiQueue.objects.get(id=queue_id, active=True)
            chauffeur = Chauffeur.objects.get(id=chauffeur_id)
            entry = QueueEntry.objects.get(queue=queue, chauffeur=chauffeur)
            
            # Get queue position and waiting count
            position = entry.get_queue_position()
            waiting_entries = queue.get_waiting_entries()
            total_waiting = waiting_entries.count()
            
            # Get pending notifications
            pending_notifications = QueueNotification.objects.filter(
                queue_entry=entry,
                response=QueueNotification.ResponseType.PENDING
            ).order_by('-notification_time')
            
            has_pending_notification = pending_notifications.exists()
            notification_data = None
            
            if has_pending_notification:
                notification = pending_notifications.first()
                notification_data = {
                    'id': notification.id,
                    'notification_time': notification.notification_time.isoformat(),
                    'is_expired': notification.is_expired(),
                }
            
            return JsonResponse({
                'success': True,
                'status': entry.get_status_display(),
                'status_code': entry.status,
                'position': position,
                'total_waiting': total_waiting,
                'has_notification': has_pending_notification,
                'notification': notification_data,
                'last_updated': timezone.now().isoformat(),
            })
            
        except Exception as e:
            return JsonResponse({
                'success': False,
                'error': str(e)
            }, status=400)


@method_decorator(csrf_exempt, name='dispatch')
class NotificationResponseView(View):
    """Handle chauffeur responses to notifications."""
    
    def post(self, request):
        """Process notification response."""
        try:
            data = json.loads(request.body)
            notification_id = data.get('notification_id')
            response_type = data.get('response')  # 'accepted' or 'declined'
            
            if not all([notification_id, response_type]):
                return JsonResponse({
                    'success': False,
                    'error': 'Missing required fields'
                }, status=400)
            
            if response_type not in ['accepted', 'declined']:
                return JsonResponse({
                    'success': False,
                    'error': 'Invalid response type'
                }, status=400)
            
            notification = get_object_or_404(QueueNotification, id=notification_id)
            
            # Check if notification is still valid
            if notification.response != QueueNotification.ResponseType.PENDING:
                return JsonResponse({
                    'success': False,
                    'error': 'Notification has already been responded to'
                }, status=400)
            
            if notification.is_expired():
                return JsonResponse({
                    'success': False,
                    'error': 'Notification has expired'
                }, status=400)
            
            # Process response
            queue_service = QueueService()
            if response_type == 'accepted':
                notification.respond(QueueNotification.ResponseType.ACCEPTED)
                message = "You have accepted the notification. Please proceed to pickup zone."
                # Trigger next notifications if needed
                queue_service.process_queue_notifications(notification.queue_entry.queue)
            else:
                notification.respond(QueueNotification.ResponseType.DECLINED)
                message = "You have declined. You remain in the queue."
                # Notify next chauffeur immediately
                queue_service.process_queue_notifications(notification.queue_entry.queue)
            
            return JsonResponse({
                'success': True,
                'message': message
            })
            
        except Exception as e:
            return JsonResponse({
                'success': False,
                'error': str(e)
            }, status=500)


class ManualTriggerView(View):
    """Manual trigger for testing - simulates sensor detection of available slots."""
    
    def get(self, request, queue_id):
        """Display manual trigger form."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
        
        context = {
            'queue': queue,
            'waiting_count': queue.get_waiting_entries().count(),
        }
        return render(request, 'queueing/manual_trigger.html', context)
    
    def post(self, request, queue_id):
        """Process manual trigger."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
        slots_available = int(request.POST.get('slots_available', 1))
        
        try:
            queue_service = QueueService()
            notified_count = queue_service.notify_next_chauffeurs(queue, slots_available)
            
            if notified_count > 0:
                messages.success(request, f'Notified {notified_count} chauffeur(s) to proceed.')
            else:
                messages.info(request, 'No chauffeurs in queue to notify.')
                
        except Exception as e:
            messages.error(request, f'Error: {str(e)}')
        
        return redirect('queueing:manual_trigger', queue_id=queue_id)
