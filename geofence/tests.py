from django.test import TestCase, Client
from django.contrib.gis.geos import Polygon
from queueing.models import TaxiQueue
from geofence.models import BufferZone, PickupZone
from django.urls import reverse

class GeofenceAPITest(TestCase):
    def setUp(self):
        # small square around (4.895, 52.33)
        poly = Polygon(
            ((4.894, 52.329), (4.896, 52.329), (4.896, 52.331), (4.894, 52.331), (4.894, 52.329)),
            srid=4326
        )
        self.bz = BufferZone.objects.create(name="testzone", zone=poly, active=True)
        # Create a pickup zone for the test queue.
        self.pz = PickupZone.objects.create(name="testpickup", active=True)
        # create a queue pointing to the created pickup zone
        self.q = TaxiQueue.objects.create(buffer_zone=self.bz, pickup_zone=self.pz, name="testqueue", active=True)
        self.client = Client()

    def test_validate_inside(self):
        url = reverse('geofence:validate_location')
        # centroid
        lat = self.bz.zone.centroid.y
        lng = self.bz.zone.centroid.x
        resp = self.client.post(url, data={'selected_queue_id': self.q.id, 'lat': lat, 'lng': lng}, content_type='application/json')
        self.assertEqual(resp.status_code, 200)
        self.assertTrue(resp.json().get('is_valid'))

    def test_validate_outside(self):
        url = reverse('geofence:validate_location')
        resp = self.client.post(url, data={'selected_queue_id': self.q.id, 'lat': 50.0, 'lng': 4.0}, content_type='application/json')
        self.assertIn(resp.status_code, (400, 200))
        self.assertFalse(resp.json().get('is_valid', False))
