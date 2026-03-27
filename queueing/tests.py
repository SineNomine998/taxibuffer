from django.test import TestCase, RequestFactory
from django.contrib.gis.geos import Point, Polygon
from django.utils import timezone
from unittest.mock import patch, MagicMock
import uuid
import json

from accounts.models import Chauffeur, ChauffeurVehicle, VehicleType, User
from geofence.models import BufferZone, PickupZone
from queueing.models import TaxiQueue, QueueEntry, QueueNotification
from queueing.views import QueueStatusAPIView
from queueing.services import QueueService


class AutomaticDequeueingTestCase(TestCase):
    """
    Test suite for automatic dequeuing feature.
    
    This tests the ability of the system to automatically remove chauffeurs
    from the queue when they leave the designated buffer zone.
    """

    def setUp(self):
        """
        Set up test fixtures: users, chauffeurs, zones, and queues.
        
        TECHNICAL CONTEXT:
        - Creates a Buffer Zone as a polygon (simulating Rotterdam harbor area)
        - Creates a Pickup Zone for taxi pickup
        - Creates a TaxiQueue linking the two zones
        - Creates test chauffeurs with vehicles
        """
        # Create users
        self.user1 = User.objects.create_user(
            username='chauffeur1',
            email='driver1@example.com',
            password='testpass123',
            first_name='John',
            last_name='Doe'
        )
        self.user1.is_chauffeur = True
        self.user1.save()

        self.user2 = User.objects.create_user(
            username='chauffeur2',
            email='driver2@example.com',
            password='testpass123',
            first_name='Jane',
            last_name='Smith'
        )
        self.user2.is_chauffeur = True
        self.user2.save()

        # Create chauffeurs
        self.chauffeur1 = Chauffeur.objects.create(
            user=self.user1,
            taxi_license_number='1234'
        )
        self.chauffeur2 = Chauffeur.objects.create(
            user=self.user2,
            taxi_license_number='5678'
        )

        # Create vehicles
        self.vehicle1 = ChauffeurVehicle.objects.create(
            chauffeur=self.chauffeur1,
            license_plate='AB-12-XY',
            nickname='Yellow Taxi',
            vehicle_type=VehicleType.AUTO,
            is_current=True,
            is_active=True
        )
        self.vehicle2 = ChauffeurVehicle.objects.create(
            chauffeur=self.chauffeur2,
            license_plate='CD-34-ZZ',
            nickname='White Taxi',
            vehicle_type=VehicleType.AUTO,
            is_current=True,
            is_active=True
        )

        # Create a buffer zone polygon (simulating Rotterdam area)
        # Coordinates roughly around Rotterdam Harbor
        self.buffer_zone = BufferZone.objects.create(
            name='Rotterdam Harbor Buffer',
            zone=Polygon([
                (4.2700, 51.9200),  # Top-left
                (4.2900, 51.9200),  # Top-right
                (4.2900, 51.9000),  # Bottom-right
                (4.2700, 51.9000),  # Bottom-left
                (4.2700, 51.9200),  # Close polygon
            ], srid=4326),
            active=True
        )

        # Create a pickup zone
        self.pickup_zone = PickupZone.objects.create(
            name='Cruise Terminal',
            total_sensors=4,
            num_of_occupied_sensors=0,
            active=True
        )

        # Create a taxi queue
        self.queue = TaxiQueue.objects.create(
            buffer_zone=self.buffer_zone,
            pickup_zone=self.pickup_zone,
            name='Rotterdam Harbor Queue',
            active=True
        )

        # Set up request factory for API testing
        self.factory = RequestFactory()

    def test_chauffeur_inside_zone_stays_queued(self):
        """
        TEST 1: Chauffeur Inside Buffer Zone Should Remain Queued
        
        SCENARIO: A chauffeur is in the queue and their location is still within
        the buffer zone boundaries. They should remain in WAITING status.
        
        TECHNICAL FLOW:
        1. Create a queue entry with WAITING status
        2. Call API with coordinates inside the buffer zone
        3. Verify: Status remains WAITING, dequeued_at is None
        """
        # Create queue entry for chauffeur1 with WAITING status
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING,
            signup_location=Point(4.2800, 51.9100, srid=4326)
        )

        # Point INSIDE the buffer zone (center of the zone)
        inside_coords = {
            'lat': 51.9100,
            'lng': 4.2800
        }

        # Make API request
        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            inside_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        # Refresh from DB to get updated state
        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.WAITING)
        self.assertIsNone(entry.dequeued_at)
        print("✓ Test 1 Passed: Chauffeur inside zone remains queued")

    def test_chauffeur_left_zone_auto_dequeued(self):
        """
        TEST 2: Chauffeur Left Buffer Zone Should Be Auto-Dequeued
        
        SCENARIO: A chauffeur is in the queue but has physically moved
        outside the buffer zone polygon. The system should detect this
        and automatically update their status to LEFT_ZONE.
        
        TECHNICAL FLOW:
        1. Create queue entry with WAITING status
        2. Call API with coordinates OUTSIDE the buffer zone
        3. Verify: Status changes to LEFT_ZONE, dequeued_at is set
        4. DB transaction is atomic (all-or-nothing)
        """
        # Create queue entry for chauffeur1
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING,
            signup_location=Point(4.2800, 51.9100, srid=4326)
        )

        # Point OUTSIDE the buffer zone (far north)
        outside_coords = {
            'lat': 51.9500,  # Outside north boundary
            'lng': 4.2800
        }

        # Make API request
        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            outside_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        # Refresh from DB
        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.LEFT_ZONE)
        self.assertIsNotNone(entry.dequeued_at)
        # Verify timestamp is recent (within last 5 seconds)
        time_diff = timezone.now() - entry.dequeued_at
        self.assertLess(time_diff.total_seconds(), 5)
        print("✓ Test 2 Passed: Chauffeur outside zone is auto-dequeued")

    def test_notified_chauffeur_left_zone_auto_dequeued(self):
        """
        TEST 3: Notified Chauffeur Left Zone Should Be Auto-Dequeued
        
        SCENARIO: A chauffeur in NOTIFIED status (has been called to pickup)
        leaves the buffer zone before they can reach the pickup area.
        Should also be auto-dequeued.
        
        TECHNICAL FLOW:
        1. Create queue entry with NOTIFIED status
        2. Verify status is NOTIFIED
        3. Call API with coordinates outside zone
        4. Verify: Status changes to LEFT_ZONE
        """
        # Create queue entry with NOTIFIED status
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.NOTIFIED,
            notified_at=timezone.now(),
            signup_location=Point(4.2800, 51.9100, srid=4326)
        )

        outside_coords = {
            'lat': 51.9201,
            'lng': 4.2800
        }

        # Make API request
        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            outside_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.LEFT_ZONE)
        print("✓ Test 3 Passed: Notified chauffeur leaving zone is dequeued")

    def test_dequeued_chauffeur_not_redequeued(self):
        """
        TEST 4: Already Dequeued Chauffeur Should Not Be Re-dequeued
        
        SCENARIO: A chauffeur already has LEFT_ZONE status. If they
        disappear and reappear slightly outside, we shouldn't double-dequeue them.
        
        TECHNICAL FLOW:
        1. Create entry with LEFT_ZONE status (already dequeued)
        2. Store original dequeued_at timestamp
        3. Call API with outside coordinates
        4. Verify: Status remains LEFT_ZONE, dequeued_at unchanged
        """
        original_dequeued_time = timezone.now() - timezone.timedelta(hours=1)
        
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.LEFT_ZONE,
            dequeued_at=original_dequeued_time,
            signup_location=Point(4.2800, 51.9100, srid=4326)
        )

        outside_coords = {
            'lat': 51.9500,
            'lng': 4.2800
        }

        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            outside_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.LEFT_ZONE)
        self.assertEqual(entry.dequeued_at, original_dequeued_time)
        print("✓ Test 4 Passed: Already dequeued chauffeur not re-dequeued")

    def test_invalid_coordinates_ignored(self):
        """
        TEST 5: Invalid Coordinates Should Be Gracefully Ignored
        
        SCENARIO: If the frontend sends malformed coordinates (non-numeric values),
        the system should continue functioning without errors.
        
        TECHNICAL FLOW:
        1. Create queue entry
        2. Send request with invalid lat/lng (string, None, etc)
        3. Verify: Entry status unchanged, no exception raised
        4. System handles gracefully (logs warning if needed)
        """
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        # Send invalid coordinates
        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            {'lat': 'invalid', 'lng': 'also_invalid'}
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.WAITING)
        self.assertEqual(response.status_code, 200)
        print("✓ Test 5 Passed: Invalid coordinates handled gracefully")

    def test_missing_coordinates_ignored(self):
        """
        TEST 6: Missing Coordinates Should Not Crash
        
        SCENARIO: If frontend doesn't send coordinates (old clients or lazy
        loading), the system should skip the dequeue check.
        
        TECHNICAL FLOW:
        1. Create queue entry
        2. Call API without lat/lng parameters
        3. Verify: Entry status unchanged, response is successful
        """
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        # Request with NO coordinates
        request = self.factory.get(f'/queueing/api/queue/{entry.uuid}/status/')
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        entry.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry.status, QueueEntry.Status.WAITING)
        self.assertEqual(response.status_code, 200)
        print("✓ Test 6 Passed: Missing coordinates handled gracefully")

    def test_queue_without_buffer_zone(self):
        """
        TEST 7: Queue Requires Valid Buffer Zone (DB Constraint)
        
        SCENARIO: The database enforces that every TaxiQueue MUST have a
        buffer_zone (NOT NULL constraint). This is correct design—we cannot
        evaluate auto-dequeue without knowing the zone boundaries.
        
        TECHNICAL CONTEXT:
        - buffer_zone field has NOT NULL constraint in schema
        - This is intentional: prevents invalid queue states
        - All queues must have geospatial boundaries for location checking
        
        TECHNICAL FLOW:
        1. Verify that attempts to create queue without buffer_zone fail
        2. This confirms DB integrity constraints are working
        3. Skip this edge case as it's a schema-level prevention
        """
        # The database enforces NOT NULL on buffer_zone
        # This is correct behavior—queues must have zones for auto-dequeue to work
        # So we verify that the constraint exists by attempting creation
        with self.assertRaises(Exception):
            # This should fail due to NOT NULL constraint
            queue_no_zone = TaxiQueue.objects.create(
                buffer_zone=None,  # Violates constraint
                pickup_zone=self.pickup_zone,
                name='Queue Without Zone'
            )
        
        print("✓ Test 7 Passed: DB constraint enforces buffer_zone requirement")

    def test_boundary_coordinates_precise(self):
        """
        TEST 8: Boundary Coordinates Should Be Handled Precisely
        
        SCENARIO: Test coordinates exactly on the polygon boundary.
        The system uses inclusive=True in point_in_buffer, so boundary
        points should be considered INSIDE.
        
        TECHNICAL FLOW:
        1. Get exact boundary coordinate (e.g., one of the polygon vertices)
        2. Create entry and call API with boundary point
        3. Verify: Entry stays WAITING (boundary is inside)
        """
        # Use exact polygon boundary point (top-left)
        boundary_coords = {
            'lat': 51.9200,
            'lng': 4.2700
        }

        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            boundary_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        entry.refresh_from_db()

        # ASSERTIONS
        # Boundary should be considered INSIDE (inclusive=True)
        self.assertEqual(entry.status, QueueEntry.Status.WAITING)
        print("✓ Test 8 Passed: Boundary coordinates handled correctly")

    @patch('queueing.views.logger')
    def test_dequeuing_logged(self, mock_logger):
        """
        TEST 9: Dequeuing Events Should Be Logged
        
        SCENARIO: When a chauffeur is auto-dequeued, the system should
        log this event for audit trails and debugging.
        
        TECHNICAL FLOW:
        1. Mock the logger
        2. Create entry and trigger dequeuing
        3. Verify: logger.info() was called with proper message
        """
        entry = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        outside_coords = {
            'lat': 51.9500,
            'lng': 4.2800
        }

        request = self.factory.get(
            f'/queueing/api/queue/{entry.uuid}/status/',
            outside_coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry.uuid)

        # ASSERTIONS
        # Verify logger was called
        mock_logger.info.assert_called()
        call_args = str(mock_logger.info.call_args)
        self.assertIn('Auto-dequeued', call_args)
        print("✓ Test 9 Passed: Dequeuing events are logged")

    def test_multiple_chauffeurs_independent_dequeuing(self):
        """
        TEST 10: Multiple Chauffeurs Should Be Dequeued Independently
        
        SCENARIO: When multiple chauffeurs are in the same queue, each
        one's location status should be evaluated independently.
        
        TECHNICAL FLOW:
        1. Create two queue entries in same queue
        2. Call API for first chauffeur with inside coords (stays)
        3. Call API for second chauffeur with outside coords (leaves)
        4. Verify: First is WAITING, second is LEFT_ZONE
        """
        entry1 = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        entry2 = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur2,
            status=QueueEntry.Status.WAITING
        )

        # Chauffeur 1 stays inside
        inside_coords = {'lat': 51.9100, 'lng': 4.2800}
        request1 = self.factory.get(
            f'/queueing/api/queue/{entry1.uuid}/status/',
            inside_coords
        )
        view = QueueStatusAPIView.as_view()
        view(request1, entry_uuid=entry1.uuid)

        # Chauffeur 2 goes outside
        outside_coords = {'lat': 51.9500, 'lng': 4.2800}
        request2 = self.factory.get(
            f'/queueing/api/queue/{entry2.uuid}/status/',
            outside_coords
        )
        view(request2, entry_uuid=entry2.uuid)

        entry1.refresh_from_db()
        entry2.refresh_from_db()

        # ASSERTIONS
        self.assertEqual(entry1.status, QueueEntry.Status.WAITING)
        self.assertEqual(entry2.status, QueueEntry.Status.LEFT_ZONE)
        print("✓ Test 10 Passed: Multiple chauffeurs dequeued independently")

    def test_api_response_includes_waiting_people_positions(self):
        """
        TEST 11: API Response Should Include Positions in Waiting People List
        
        SCENARIO: The updated API should return position data for each
        waiting person so the frontend can display the queue order.
        
        TECHNICAL FLOW:
        1. Create multiple queue entries
        2. Call API status endpoint
        3. Parse JSON response
        4. Verify: waiting_people list includes position field for each person
        """
        entry1 = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur1,
            status=QueueEntry.Status.WAITING
        )

        entry2 = QueueEntry.objects.create(
            queue=self.queue,
            chauffeur=self.chauffeur2,
            status=QueueEntry.Status.WAITING
        )

        coords = {'lat': 51.9100, 'lng': 4.2800}
        request = self.factory.get(
            f'/queueing/api/queue/{entry1.uuid}/status/',
            coords
        )
        view = QueueStatusAPIView.as_view()
        response = view(request, entry_uuid=entry1.uuid)

        # Parse response
        response_data = json.loads(response.content)

        # ASSERTIONS
        self.assertTrue(response_data['success'])
        self.assertIn('waiting_people', response_data)
        self.assertGreater(len(response_data['waiting_people']), 0)
        
        # Each person should have position
        for person in response_data['waiting_people']:
            self.assertIn('position', person)
            self.assertIsNotNone(person['position'])
        
        print("✓ Test 11 Passed: API response includes positions")
