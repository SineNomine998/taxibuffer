import re
from rest_framework import serializers
from django.contrib.auth import get_user_model

from .vehicle import MobileVehicleSerializer
from compliance.services import get_active_privacy_policy

User = get_user_model()


class MobileSignUpSerializer(serializers.Serializer):
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    taxi_license_number = serializers.CharField(max_length=100)
    password = serializers.CharField(write_only=True, min_length=8)
    password_confirm = serializers.CharField(write_only=True)
    vehicles = MobileVehicleSerializer(many=True)
    privacy_policy_version = serializers.CharField()
    privacy_policy_accepted = serializers.BooleanField()

    def validate_email(self, value):
        value = value.lower().strip()

        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError(
                "Er bestaat al een account met dit e-mailadres."
            )

        return value

    def validate_taxi_license_number(self, value):
        # Commented out for now as we don't check the validity/reliability of any user's RTX-number
        # May be added back in the future depending on the situation
        # if User.objects.filter(taxi_license_number=attrs["taxi_license_number"]).exists():
        #     raise serializers.ValidationError({"taxi_license_number": "Dit RTX-nummer is al geregistreerd."})

        return value.strip().upper()

    def validate(self, attrs):
        if attrs["password"] != attrs["password_confirm"]:
            raise serializers.ValidationError(
                {"password_confirm": "Wachtwoorden komen niet overeen."}
            )

        vehicles = attrs.get("vehicles", [])
        if not vehicles:
            raise serializers.ValidationError(
                {"vehicles": "Voeg minimaal 1 voertuig toe om verder te gaan."}
            )

        plates = [v["license_plate"].upper() for v in vehicles]
        if len(plates) != len(set(plates)):
            raise serializers.ValidationError(
                {"vehicles": "Een kenteken is dubbel toegevoegd."}
            )

        current_count = sum(1 for v in vehicles if v.get("is_current"))
        if current_count > 1:
            raise serializers.ValidationError(
                {"vehicles": "Er mag maar één huidig voertuig zijn."}
            )

        policy = get_active_privacy_policy()

        if policy is None:
            raise serializers.ValidationError(
                {"privacy_policy": "Geen actieve privacyverklaring gevonden."}
            )

        if not attrs.get("privacy_policy_accepted"):
            raise serializers.ValidationError(
                {"privacy_policy": "Privacyverklaring moet worden geaccepteerd."}
            )

        if attrs.get("privacy_policy_version") != policy.version:
            raise serializers.ValidationError(
                {"privacy_policy": "Privacyverklaring versie komt niet overeen."}
            )

        return attrs
