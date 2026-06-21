from rest_framework import serializers
from django.contrib.auth import get_user_model
from .vehicle import MobileVehicleSerializer

User = get_user_model()


class MobileAccountProfileSerializer(serializers.Serializer):
    first_name = serializers.CharField(max_length=150)
    last_name = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    taxi_license_number = serializers.CharField(max_length=100)

    def validate_first_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Voornaam is verplicht.")
        return value

    def validate_last_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Achternaam is verplicht.")
        return value

    def validate_email(self, value):
        value = value.lower().strip()
        request = self.context.get("request")

        queryset = User.objects.filter(email__iexact=value)
        if request and request.user.is_authenticated:
            queryset = queryset.exclude(pk=request.user.pk)

        if queryset.exists():
            raise serializers.ValidationError(
                "Er bestaat al een account met dit e-mailadres."
            )

        return value

    def validate_taxi_license_number(self, value):
        value = value.strip().upper()
        if not value:
            raise serializers.ValidationError("RTX-nummer is verplicht.")
        return value


class MobileAccountSerializer(serializers.Serializer):
    profile = MobileAccountProfileSerializer()
    vehicles = MobileVehicleSerializer(many=True)
    current_vehicle = MobileVehicleSerializer(allow_null=True)
