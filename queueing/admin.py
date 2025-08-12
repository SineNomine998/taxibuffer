"""
Django Admin configuration for taxi queue management.
Provides comprehensive admin interface for monitoring and managing queues.
"""

from django.contrib import admin
from django.utils.html import format_html
from django.urls import reverse
from django.utils import timezone
from django.db.models import Count, Q
from django.contrib.admin import SimpleListFilter

from .models import TaxiQueue, QueueEntry, QueueNotification


class QueueEntryInline(admin.TabularInline):
    """Inline display of queue entries within TaxiQueue admin."""
    model = QueueEntry
    extra = 0
    readonly_fields = ('uuid', 'created_at', 'updated_at', 'get_queue_position')
    fields = (
        'chauffeur', 'status', 'get_queue_position', 
        'created_at', 'notified_at', 'dequeued_at'
    )
    
    def get_queue_position(self, obj):
        """Display queue position."""
        if obj.status == QueueEntry.Status.WAITING:
            return obj.get_queue_position()
        return '-'
    get_queue_position.short_description = 'Position'

    def get_queryset(self, request):
        """Optimize queryset with select_related."""
        return super().get_queryset(request).select_related('chauffeur', 'chauffeur__user')


class StatusFilter(SimpleListFilter):
    """Custom filter for queue entry status."""
    title = 'Status'
    parameter_name = 'status'

    def lookups(self, request, model_admin):
        return QueueEntry.Status.choices

    def queryset(self, request, queryset):
        if self.value():
            return queryset.filter(status=self.value())
        return queryset


class NotificationStatusFilter(SimpleListFilter):
    """Filter for notification response status."""
    title = 'Notification Status'
    parameter_name = 'notification_status'

    def lookups(self, request, model_admin):
        return QueueNotification.ResponseType.choices

    def queryset(self, request, queryset):
        if self.value():
            return queryset.filter(notifications__response=self.value()).distinct()
        return queryset


@admin.register(TaxiQueue)
class TaxiQueueAdmin(admin.ModelAdmin):
    """Admin interface for TaxiQueue model."""
    
    list_display = (
        'name', 'buffer_zone', 'pickup_zone', 'get_waiting_count', 
        'get_notified_count', 'get_available_slots', 'notification_timeout_minutes', 
        'active', 'created_at'
    )
    list_filter = ('active', 'created_at', 'buffer_zone', 'pickup_zone')
    search_fields = ('name', 'buffer_zone__name', 'pickup_zone__name')
    readonly_fields = ('uuid', 'created_at', 'updated_at', 'get_queue_stats')
    
    fieldsets = (
        ('Basic Information', {
            'fields': ('name', 'buffer_zone', 'pickup_zone', 'active')
        }),
        ('Configuration', {
            'fields': ('notification_timeout_minutes',)
        }),
        ('Statistics', {
            'fields': ('get_queue_stats',),
            'classes': ('collapse',)
        }),
        ('Metadata', {
            'fields': ('uuid', 'created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    inlines = [QueueEntryInline]
    
    def get_waiting_count(self, obj):
        """Get count of waiting chauffeurs."""
        return obj.entries.filter(status=QueueEntry.Status.WAITING).count()
    get_waiting_count.short_description = 'Waiting'
    get_waiting_count.admin_order_field = 'waiting_count'
    
    def get_notified_count(self, obj):
        """Get count of notified chauffeurs."""
        return obj.entries.filter(status=QueueEntry.Status.NOTIFIED).count()
    get_notified_count.short_description = 'Notified'
    
    def get_available_slots(self, obj):
        """Display available slots in pickup zone."""
        available = obj.pickup_zone.get_available_slots()
        total = obj.pickup_zone.total_sensors
        
        if available > 0:
            color = 'green'
        elif available == 0:
            color = 'orange'
        else:
            color = 'red'
            
        return format_html(
            '<span style="color: {};">{}/{}</span>',
            color, available, total
        )
    get_available_slots.short_description = 'Available Slots'
    
    def get_queue_stats(self, obj):
        """Display comprehensive queue statistics."""
        stats = obj.entries.aggregate(
            waiting=Count('id', filter=Q(status=QueueEntry.Status.WAITING)),
            notified=Count('id', filter=Q(status=QueueEntry.Status.NOTIFIED)),
            dequeued=Count('id', filter=Q(status=QueueEntry.Status.DEQUEUED)),
            declined=Count('id', filter=Q(status=QueueEntry.Status.DECLINED)),
            timeout=Count('id', filter=Q(status=QueueEntry.Status.TIMEOUT)),
            left_zone=Count('id', filter=Q(status=QueueEntry.Status.LEFT_ZONE)),
        )
        
        return format_html(
            """
            <table>
                <tr><td><strong>Waiting:</strong></td><td>{waiting}</td></tr>
                <tr><td><strong>Notified:</strong></td><td>{notified}</td></tr>
                <tr><td><strong>Dequeued:</strong></td><td style="color: green;">{dequeued}</td></tr>
                <tr><td><strong>Declined:</strong></td><td style="color: orange;">{declined}</td></tr>
                <tr><td><strong>Timeout:</strong></td><td style="color: red;">{timeout}</td></tr>
                <tr><td><strong>Left Zone:</strong></td><td style="color: red;">{left_zone}</td></tr>
            </table>
            """,
            **stats
        )
    get_queue_stats.short_description = 'Queue Statistics'
    
    def get_queryset(self, request):
        """Optimize queryset with annotations."""
        return super().get_queryset(request).select_related(
            'buffer_zone', 'pickup_zone'
        ).annotate(
            waiting_count=Count('entries', filter=Q(entries__status=QueueEntry.Status.WAITING))
        )


@admin.register(QueueEntry)
class QueueEntryAdmin(admin.ModelAdmin):
    """Admin interface for QueueEntry model."""
    
    list_display = (
        'get_chauffeur_info', 'queue', 'status', 'get_queue_position', 
        'created_at', 'notified_at', 'dequeued_at', 'get_notification_status'
    )
    list_filter = (
        StatusFilter, NotificationStatusFilter, 'created_at', 
        'queue__buffer_zone', 'queue__pickup_zone'
    )
    search_fields = (
        'chauffeur__license_plate', 'chauffeur__taxi_license_number',
        'chauffeur__user__username', 'queue__name'
    )
    readonly_fields = (
        'uuid', 'created_at', 'updated_at', 'get_queue_position',
        'get_notification_history', 'get_location_info'
    )
    
    fieldsets = (
        ('Queue Information', {
            'fields': ('queue', 'chauffeur', 'status', 'get_queue_position')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'notified_at', 'dequeued_at', 'updated_at')
        }),
        ('Location', {
            'fields': ('signup_location', 'get_location_info'),
            'classes': ('collapse',)
        }),
        ('Notification History', {
            'fields': ('get_notification_history',),
            'classes': ('collapse',)
        }),
        ('Metadata', {
            'fields': ('uuid',),
            'classes': ('collapse',)
        }),
    )
    
    def get_chauffeur_info(self, obj):
        """Display chauffeur information with link."""
        chauffeur_url = reverse('admin:accounts_chauffeur_change', args=[obj.chauffeur.pk])
        return format_html(
            '<a href="{}">{}</a><br/><small>{}</small>',
            chauffeur_url,
            obj.chauffeur.license_plate,
            obj.chauffeur.taxi_license_number
        )
    get_chauffeur_info.short_description = 'Chauffeur'
    get_chauffeur_info.admin_order_field = 'chauffeur__license_plate'
    
    def get_queue_position(self, obj):
        """Display current queue position."""
        if obj.status == QueueEntry.Status.WAITING:
            position = obj.get_queue_position()
            return format_html('<strong>#{}</strong>', position) if position else '-'
        return '-'
    get_queue_position.short_description = 'Position'
    
    def get_notification_status(self, obj):
        """Display latest notification status."""
        latest_notification = obj.notifications.order_by('-notification_time').first()
        if not latest_notification:
            return '-'
        
        status = latest_notification.get_response_display()
        if latest_notification.response == QueueNotification.ResponseType.PENDING:
            if latest_notification.is_expired():
                return format_html('<span style="color: red;">Expired</span>')
            return format_html('<span style="color: orange;">Pending</span>')
        elif latest_notification.response == QueueNotification.ResponseType.ACCEPTED:
            return format_html('<span style="color: green;">{}</span>', status)
        elif latest_notification.response == QueueNotification.ResponseType.DECLINED:
            return format_html('<span style="color: orange;">{}</span>', status)
        else:
            return format_html('<span style="color: red;">{}</span>', status)
    get_notification_status.short_description = 'Notification Status'
    
    def get_notification_history(self, obj):
        """Display notification history."""
        notifications = obj.notifications.order_by('-notification_time')
        if not notifications.exists():
            return 'No notifications sent'
        
        history = []
        for notification in notifications:
            response_time = ''
            if notification.response_time:
                response_seconds = notification.get_response_time_seconds()
                response_time = f' (responded in {response_seconds:.0f}s)'
            
            history.append(
                f"{notification.notification_time.strftime('%Y-%m-%d %H:%M')} - "
                f"{notification.get_response_display()}{response_time}"
            )
        
        return format_html('<br/>'.join(history))
    get_notification_history.short_description = 'Notification History'
    
    def get_location_info(self, obj):
        """Display location information."""
        if not obj.signup_location:
            return 'No location recorded'
        
        return format_html(
            'Lat: {:.6f}, Lon: {:.6f}',
            obj.signup_location.y,
            obj.signup_location.x
        )
    get_location_info.short_description = 'Signup Location'
    
    def get_queryset(self, request):
        """Optimize queryset."""
        return super().get_queryset(request).select_related(
            'chauffeur', 'chauffeur__user', 'queue', 
            'queue__buffer_zone', 'queue__pickup_zone'
        ).prefetch_related('notifications')
    
    actions = ['mark_as_left_zone', 'force_timeout_notifications']
    
    def mark_as_left_zone(self, request, queryset):
        """Admin action to mark entries as left zone."""
        count = 0
        for entry in queryset:
            if entry.status in [QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED]:
                entry.status = QueueEntry.Status.LEFT_ZONE
                entry.save()
                count += 1
        
        self.message_user(request, f'{count} entries marked as left zone.')
    mark_as_left_zone.short_description = 'Mark selected entries as left zone'
    
    def force_timeout_notifications(self, request, queryset):
        """Admin action to force timeout pending notifications."""
        count = 0
        for entry in queryset.filter(status=QueueEntry.Status.NOTIFIED):
            pending_notifications = entry.notifications.filter(
                response=QueueNotification.ResponseType.PENDING
            )
            for notification in pending_notifications:
                notification.respond(QueueNotification.ResponseType.TIMEOUT)
                count += 1
        
        self.message_user(request, f'{count} notifications timed out.')
    force_timeout_notifications.short_description = 'Force timeout pending notifications'


@admin.register(QueueNotification)
class QueueNotificationAdmin(admin.ModelAdmin):
    """Admin interface for QueueNotification model."""
    
    list_display = (
        'get_chauffeur_info', 'get_queue_name', 'notification_time', 
        'response', 'response_time', 'get_response_duration', 'get_status'
    )
    list_filter = (
        'response', 'notification_time', 
        'queue_entry__queue__buffer_zone', 'queue_entry__queue__pickup_zone'
    )
    search_fields = (
        'queue_entry__chauffeur__license_plate',
        'queue_entry__chauffeur__taxi_license_number',
        'queue_entry__queue__name'
    )
    readonly_fields = (
        'uuid', 'created_at', 'updated_at', 'get_response_duration',
        'get_expiry_info'
    )
    
    fieldsets = (
        ('Notification Details', {
            'fields': ('queue_entry', 'notification_time', 'response', 'response_time')
        }),
        ('Analysis', {
            'fields': ('get_response_duration', 'get_expiry_info'),
            'classes': ('collapse',)
        }),
        ('Metadata', {
            'fields': ('uuid', 'created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
    
    def get_chauffeur_info(self, obj):
        """Display chauffeur information."""
        return f"{obj.queue_entry.chauffeur.license_plate}"
    get_chauffeur_info.short_description = 'License Plate'
    get_chauffeur_info.admin_order_field = 'queue_entry__chauffeur__license_plate'
    
    def get_queue_name(self, obj):
        """Display queue name."""
        return obj.queue_entry.queue.name
    get_queue_name.short_description = 'Queue'
    get_queue_name.admin_order_field = 'queue_entry__queue__name'
    
    def get_response_duration(self, obj):
        """Display response duration."""
        duration = obj.get_response_time_seconds()
        if duration is None:
            return 'No response yet'
        
        minutes = int(duration // 60)
        seconds = int(duration % 60)
        
        if minutes > 0:
            return f'{minutes}m {seconds}s'
        return f'{seconds}s'
    get_response_duration.short_description = 'Response Time'
    
    def get_status(self, obj):
        """Display notification status with color."""
        if obj.response == QueueNotification.ResponseType.PENDING:
            if obj.is_expired():
                return format_html('<span style="color: red;">Expired</span>')
            return format_html('<span style="color: orange;">Pending</span>')
        elif obj.response == QueueNotification.ResponseType.ACCEPTED:
            return format_html('<span style="color: green;">Accepted</span>')
        elif obj.response == QueueNotification.ResponseType.DECLINED:
            return format_html('<span style="color: orange;">Declined</span>')
        else:
            return format_html('<span style="color: red;">Timeout</span>')
    get_status.short_description = 'Status'
    
    def get_expiry_info(self, obj):
        """Display expiry information."""
        if obj.response != QueueNotification.ResponseType.PENDING:
            return f"Completed: {obj.get_response_display()}"
        
        timeout_minutes = obj.queue_entry.queue.notification_timeout_minutes
        expiry_time = obj.notification_time + timezone.timedelta(minutes=timeout_minutes)
        
        if timezone.now() > expiry_time:
            return format_html('<span style="color: red;">Expired</span>')
        
        time_left = expiry_time - timezone.now()
        minutes_left = int(time_left.total_seconds() / 60)
        
        return format_html(
            'Expires at: {}<br/>Time left: {} minutes',
            expiry_time.strftime('%Y-%m-%d %H:%M:%S'),
            minutes_left
        )
    get_expiry_info.short_description = 'Expiry Information'
    
    def get_queryset(self, request):
        """Optimize queryset."""
        return super().get_queryset(request).select_related(
            'queue_entry', 'queue_entry__chauffeur', 
            'queue_entry__queue', 'queue_entry__queue__buffer_zone',
            'queue_entry__queue__pickup_zone'
        )