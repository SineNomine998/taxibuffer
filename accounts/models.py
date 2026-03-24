from django.contrib.gis.db import models
import uuid
from django.contrib.auth.models import AbstractUser
from django.utils.translation import gettext_lazy as _
from django.db.models import Q

# Create your models here.


class User(AbstractUser):
    """Custom abstract user model for the application."""

    uuid = models.UUIDField(default=uuid.uuid4, null=False, blank=False, editable=False)
    is_chauffeur = models.BooleanField(default=False)
    is_officer = models.BooleanField(default=False)

    def __str__(self):
        return self.get_username()


class VehicleType(models.TextChoices):
    AUTO = "auto", _("Auto")
    BUSJE = "busje", _("Busje")


class Chauffeur(models.Model):
    """Represents a chauffeur (taxi driver) in the system."""

    user = models.OneToOneField(
        User, on_delete=models.CASCADE, related_name="chauffeur"
    )
    taxi_license_number = models.CharField(max_length=100)  # RTX-nummer
    sign_up_time = models.DateTimeField(auto_now_add=True)
    location = models.PointField(null=True, blank=True, srid=4326)

    def get_current_vehicle(self):
        return self.vehicles.filter(is_current=True).first()

    @property
    def current_license_plate(self):
        current_vehicle = self.get_current_vehicle()
        if current_vehicle:
            return current_vehicle.license_plate
        return ""

    @property
    def current_vehicle_type(self):
        current_vehicle = self.get_current_vehicle()
        if current_vehicle:
            return current_vehicle.vehicle_type
        return None

    def __str__(self):
        plate = self.current_license_plate or "No current vehicle"
        return f"License plate: {plate} (RTX-nummer: {self.taxi_license_number})"


class Officer(models.Model):
    """Represents an officer in the system."""

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="officer")
    credentials = models.CharField(max_length=100, unique=True)

    def __str__(self):
        return f"Officer credentials: {self.credentials}"


class ChauffeurVehicle(models.Model):
    """Vehicle registry for each chauffeur account."""

    chauffeur = models.ForeignKey(
        Chauffeur, on_delete=models.CASCADE, related_name="vehicles"
    )
    license_plate = models.CharField(max_length=20)
    nickname = models.CharField(max_length=60)
    vehicle_type = models.CharField(
        max_length=10,
        choices=VehicleType.choices,
        default=VehicleType.AUTO,
        help_text="Vehicle type for queue routing",
    )
    is_current = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["chauffeur", "license_plate"],
                condition=Q(is_active=True),
                name="unique_chauffeur_license_plate",
            ),
            models.UniqueConstraint(
                fields=["chauffeur"],
                condition=Q(is_current=True, is_active=True),
                name="unique_current_vehicle_per_chauffeur",
            ),
        ]
        indexes = [
            models.Index(fields=["chauffeur", "is_current"]),
            models.Index(fields=["license_plate"]),
            models.Index(fields=["is_active"]),
        ]

    def __str__(self):
        suffix = " (current)" if self.is_current else ""
        return f"{self.nickname} - {self.license_plate}{suffix}"
