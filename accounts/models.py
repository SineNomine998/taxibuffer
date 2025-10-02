from django.contrib.gis.db import models
import uuid
from django.contrib.auth.models import AbstractUser
from django.utils.translation import gettext_lazy as _

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
    license_plate = models.CharField(max_length=10)
    taxi_license_number = models.CharField(max_length=100, unique=True)  # RTX-nummer
    vehicle_type = models.CharField(
        max_length=10,
        choices=VehicleType.choices,
        default=VehicleType.AUTO,
        help_text="Driver's vehicle type",
    )
    sign_up_time = models.DateTimeField(auto_now_add=True)
    location = models.PointField(null=True, blank=True, srid=4326)

    def __str__(self):
        return f"License plate: {self.license_plate} (taxi: {self.taxi_license_number})"


class Officer(models.Model):
    """Represents an officer in the system."""

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="officer")
    credentials = models.CharField(max_length=100, unique=True)

    def __str__(self):
        return f"Officer credentials: {self.credentials}"
