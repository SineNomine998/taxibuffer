from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.db import transaction

from accounts.models import Chauffeur, ChauffeurVehicle, VehicleType
from accounts.choices import TTO_CHOICES
from mobile_api.serializers import normalize_license_plate
from compliance.services import accept_active_privacy_policy, accept_active_terms_of_use


class Command(BaseCommand):
    help = "Create or update the Google Play review chauffeur account."

    def add_arguments(self, parser):
        parser.add_argument("--email", required=True)
        parser.add_argument("--password", required=True)

    @transaction.atomic
    def handle(self, *args, **options):
        User = get_user_model()

        email = options["email"].strip().lower()
        password = options["password"]

        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                "username": email,
                "first_name": "Google2",  # TODO: Change this
                "last_name": "Reviewer2",  # TODO: Change this
                "is_chauffeur": True,
                "is_active": True,
            },
        )

        user.username = email
        user.first_name = "Google2"  # TODO: Change this
        user.last_name = "Reviewer2"  # TODO: Change this
        user.is_chauffeur = True
        user.is_active = True
        user.set_password(password)
        user.save()

        tto_value = TTO_CHOICES[0][0]

        chauffeur, _ = Chauffeur.objects.get_or_create(
            user=user,
            defaults={
                "taxi_license_number": "REVIEW123",
                "tto": tto_value,
                "phone_number": "0612345678",
                "is_review_account": True,
            },
        )

        chauffeur.taxi_license_number = "REVIEW123"
        chauffeur.tto = tto_value
        chauffeur.phone_number = "0612345678"
        chauffeur.is_review_account = True
        chauffeur.save()

        ChauffeurVehicle.objects.update_or_create(
            chauffeur=chauffeur,
            license_plate=normalize_license_plate("TB-REV-1"),
            defaults={
                "nickname": "Review vehicle",
                "vehicle_type": VehicleType.AUTO,
                "is_current": True,
                "is_active": True,
            },
        )

        ChauffeurVehicle.objects.filter(chauffeur=chauffeur).exclude(
            license_plate=normalize_license_plate("TB-REV-1")
        ).update(is_current=False)

        accept_active_privacy_policy(chauffeur=chauffeur, request=None)
        accept_active_terms_of_use(chauffeur=chauffeur, request=None)

        self.stdout.write(self.style.SUCCESS(f"Review account ready: {email}"))
