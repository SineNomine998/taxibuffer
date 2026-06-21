import re
from rest_framework import serializers
from accounts.models import VehicleType


def normalize_license_plate(value: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", value.upper().strip())


class MobileVehicleSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    license_plate = serializers.CharField(max_length=20)
    nickname = serializers.CharField(max_length=60, allow_blank=True, required=False)
    vehicle_type = serializers.ChoiceField(
        choices=[VehicleType.AUTO, VehicleType.BUSJE],
        default=VehicleType.AUTO,
    )
    is_current = serializers.BooleanField(default=False)

    def validate_license_plate(self, value):
        normalized = normalize_license_plate(value)

        if len(normalized) < 5 or len(normalized) > 8:
            raise serializers.ValidationError("Vul een geldig kenteken in.")

        return normalized
