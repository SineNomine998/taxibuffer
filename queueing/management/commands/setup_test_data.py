from django.core.management.base import BaseCommand
from django.contrib.gis.geos import Polygon
from geofence.models import BufferZone, PickupZone
from queueing.models import TaxiQueue
from sensors.models import Sensor


class Command(BaseCommand):
    help = 'Set up test data for the taxi queue system'

    def handle(self, *args, **options):
        self.stdout.write('Creating test data...')
        
        # Create buffer zone
        buffer_coords = [
            [4.8851, 52.3676],  # Amsterdam coordinates (lng, lat)
            [4.8851, 52.3776],
            [4.8951, 52.3776],
            [4.8951, 52.3676],
            [4.8851, 52.3676]
        ]
        buffer_polygon = Polygon(buffer_coords)
        
        buffer_zone, created = BufferZone.objects.get_or_create(
            name='Central Amsterdam Buffer Zone',
            defaults={
                'zone': buffer_polygon,
                'active': True
            }
        )
        
        if created:
            self.stdout.write(self.style.SUCCESS(f'Created buffer zone: {buffer_zone.name}'))
        else:
            self.stdout.write(f'Buffer zone already exists: {buffer_zone.name}')
        
        # Create pickup zone
        pickup_zone, created = PickupZone.objects.get_or_create(
            name='Airport Pickup Zone',
            defaults={
                'total_sensors': 7,
                'num_of_occupied_sensors': 0,
                'active': True
            }
        )
        
        if created:
            self.stdout.write(self.style.SUCCESS(f'Created pickup zone: {pickup_zone.name}'))
        else:
            self.stdout.write(f'Pickup zone already exists: {pickup_zone.name}')
        
        # Create sensors for pickup zone
        for i in range(1, 8):  # 7 sensors
            sensor, created = Sensor.objects.get_or_create(
                sensor_id=f'SENSOR_{i:02d}',
                pickup_zone=pickup_zone,
                defaults={
                    'active': True
                }
            )
            if created:
                self.stdout.write(f'Created sensor: {sensor.sensor_id}')
        
        # Create taxi queue
        queue, created = TaxiQueue.objects.get_or_create(
            buffer_zone=buffer_zone,
            pickup_zone=pickup_zone,
            defaults={
                'notification_timeout_minutes': 2,
                'active': True
            }
        )
        
        if created:
            self.stdout.write(self.style.SUCCESS(f'Created taxi queue: {queue.name}'))
        else:
            self.stdout.write(f'Taxi queue already exists: {queue.name}')
        
        self.stdout.write(
            self.style.SUCCESS(
                '\nTest data setup complete!\n'
                'You can now:\n'
                '1. Visit /queueing/signup/ to add chauffeurs to the queue\n'
                f'2. Visit /queueing/queue/{queue.id}/trigger/ to manually trigger notifications\n'
                '3. Test the notification system with multiple chauffeurs'
            )
        )
