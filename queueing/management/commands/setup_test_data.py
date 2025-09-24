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
        buffer_coords = [ # Laan op Zuid, Rotterdam
            [
              4.500310583560008,
              51.9083638071713
            ],
            [
              4.497139253806097,
              51.90552322583062
            ],
            [
              4.5028410550964395,
              51.90372960740041
            ],
            [
              4.5055836932230875,
              51.90619761848478
            ],
            [
              4.500310583560008,
              51.9083638071713
            ]
        ]
        buffer_polygon = Polygon(buffer_coords)
        
        buffer_zone, created = BufferZone.objects.get_or_create(
            name='Laan op Zuid Rotterdam Buffer Zone',
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
            name='Cruise Terminal Rotterdam',
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
        
        # Create additional pickup zones for variety
        additional_zones = [
            # ('Amsterdam Airport Schiphol', 5),
            # ('Central Station Amsterdam', 4),
            # ('RAI Convention Center', 6),
        ]
        
        for zone_name, sensor_count in additional_zones:
            zone, created = PickupZone.objects.get_or_create(
                name=zone_name,
                defaults={
                    'total_sensors': sensor_count,
                    'num_of_occupied_sensors': 0,
                    'active': True
                }
            )
            if created:
                self.stdout.write(f'Created additional pickup zone: {zone.name}')
                
                # Create additional buffer zones and queues
                additional_buffer, buffer_created = BufferZone.objects.get_or_create(
                    name=f'{zone_name} Buffer Zone',
                    defaults={
                        'zone': buffer_polygon,  # Using same polygon for simplicity
                        'active': True
                    }
                )
                
                if buffer_created:
                    # Create queue for this buffer-pickup pair
                    additional_queue, queue_created = TaxiQueue.objects.get_or_create(
                        buffer_zone=additional_buffer,
                        pickup_zone=zone,
                        defaults={
                            'notification_timeout_minutes': 2,
                            'active': True
                        }
                    )
                    if queue_created:
                        self.stdout.write(f'Created queue: {additional_queue.name}')
                
                # Create sensors for additional zones
                for i in range(1, sensor_count + 1):
                    sensor, sensor_created = Sensor.objects.get_or_create(
                        sensor_id=f'{zone_name.replace(" ", "_").upper()}_SENSOR_{i:02d}',
                        pickup_zone=zone,
                        defaults={
                            'active': True
                        }
                    )
                    if sensor_created:
                        self.stdout.write(f'Created sensor: {sensor.sensor_id}')

        # TODO: Should you really create new sensors this way?
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
                # 'notification_timeout_minutes': 2,
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
                '1. Visit /queueing/ to login as a chauffeur\n'
                f'2. Visit /queueing/admin/queue/{queue.id}/trigger/ to manually trigger notifications\n'
                '3. Test the notification system with multiple chauffeurs\n'
                '4. And visit /control/ to monitor the queue activity for all zones\n'
            )
        )
