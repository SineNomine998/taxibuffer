import logging
from django.db import transaction
from django.contrib.auth import get_user_model, authenticate
from django.contrib.auth.forms import PasswordResetForm
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from mobile_api.serializers import (
    MobileLoginSerializer,
    MobileSignUpSerializer,
    normalize_license_plate,
    MobileAccountProfileSerializer,
    MobileAccountSerializer,
    MobileVehicleSerializer,
)
from accounts.models import Chauffeur, ChauffeurVehicle, VehicleType
from queueing.views import _build_unique_username

logger = logging.getLogger(__name__)

User = get_user_model()


def get_current_chauffeur(user):
    chauffeur = getattr(user, "chauffeur", None)
    if chauffeur is None:
        raise PermissionDenied("Geen chauffeurprofiel gevonden.")
    return chauffeur


class MobileLoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = MobileLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        email = serializer.validated_data["email"]
        password = serializer.validated_data["password"]

        user = authenticate(request, username=email, password=password)

        if user is None:
            return Response(
                {"detail": "Invalid email address or password."},
                status=status.HTTP_401_UNAUTHORIZED,
            )

        if not user.is_active:
            return Response(
                {"detail": "This account is inactive."},
                status=status.HTTP_403_FORBIDDEN,
            )

        refresh = RefreshToken.for_user(user)

        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": {
                    "id": user.id,
                    "first_name": user.first_name,
                    "last_name": user.last_name,
                    "email": user.email,
                },
            }
        )


class MobileTokenRefreshView(TokenRefreshView):
    permission_classes = [AllowAny]


class MobileLogoutView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        refresh_token = request.data.get("refresh")

        if not refresh_token:
            return Response(
                {"detail": "Refresh token is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            token = RefreshToken(refresh_token)
            token.blacklist()
        except Exception:
            return Response(
                {"detail": "Invalid refresh token."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        return Response({"detail": "Logged out successfully."})


class MobileCheckEmailView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email = request.data.get("email", "")
        exists = User.objects.filter(email__iexact=email.strip()).exists()
        return Response({"available": not exists})


class MobileSignUpView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = MobileSignUpSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # when debugging is needed, uncomment:
        # if not serializer.is_valid():
        #     logger.warning("Mobile signup validation failed: %s", serializer.errors)
        #     return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        data = serializer.validated_data

        vehicles = data["vehicles"]

        current_index = next(
            (i for i, v in enumerate(vehicles) if v.get("is_current")),
            0,
        )

        try:
            with transaction.atomic():
                username = _build_unique_username(
                    data["first_name"],
                    data["last_name"],
                    data["taxi_license_number"],
                )

                user = User.objects.create_user(
                    username=username,
                    email=data["email"],
                    password=data["password"],
                    first_name=data["first_name"],
                    last_name=data["last_name"],
                    is_chauffeur=True,
                )

                chauffeur = Chauffeur.objects.create(
                    user=user,
                    taxi_license_number=data["taxi_license_number"],
                    location=None,
                )

                for idx, vehicle in enumerate(vehicles):
                    ChauffeurVehicle.objects.create(
                        chauffeur=chauffeur,
                        license_plate=normalize_license_plate(vehicle["license_plate"]),
                        nickname=vehicle["nickname"],
                        vehicle_type=vehicle.get("vehicle_type", VehicleType.AUTO),
                        is_current=(idx == current_index),
                        is_active=True,
                    )

        except Exception:
            return Response(
                {"detail": "Account kon niet worden aangemaakt. Probeer opnieuw."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        refresh = RefreshToken.for_user(user)

        return Response(
            {
                "access": str(refresh.access_token),
                "refresh": str(refresh),
                "user": {
                    "id": user.id,
                    "first_name": user.first_name,
                    "last_name": user.last_name,
                    "email": user.email,
                    "taxi_license_number": chauffeur.taxi_license_number,
                    "current_vehicle": normalize_license_plate(
                        chauffeur.current_license_plate
                    ),
                },
            },
            status=status.HTTP_201_CREATED,
        )


class MobilePasswordResetView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email = request.data.get("email", "").strip().lower()
        if not email:
            return Response(
                {"detail": "Vul een e-mailadres in."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        form = PasswordResetForm(data={"email": email})
        if form.is_valid():
            form.save(
                request=request,
                use_https=request.is_secure(),
                email_template_name="queueing/password_reset_email.html",
                subject_template_name="queueing/password_reset_subject.txt",
                extra_email_context=None,
            )
        return Response(
            {"detail": "Als dit e-mailadres bekend is, ontvangt u een e-mail."}
        )


class MobileAccountView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        chauffeur = get_current_chauffeur(user)

        vehicles = ChauffeurVehicle.objects.filter(
            chauffeur=chauffeur,
            is_active=True,
        ).order_by("-is_current", "id")

        current_vehicle = vehicles.filter(is_current=True).first()

        profile_data = {
            "first_name": user.first_name,
            "last_name": user.last_name,
            "email": user.email,
            "taxi_license_number": chauffeur.taxi_license_number,
        }

        return Response(
            {
                "profile": MobileAccountProfileSerializer(profile_data).data,
                "vehicles": MobileVehicleSerializer(vehicles, many=True).data,
                "current_vehicle": (
                    MobileVehicleSerializer(current_vehicle).data
                    if current_vehicle
                    else None
                ),
            }
        )


class MobileAccountProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request):
        user = request.user
        chauffeur = get_current_chauffeur(user)

        serializer = MobileAccountProfileSerializer(
            data=request.data,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        user.first_name = data["first_name"]
        user.last_name = data["last_name"]
        user.email = data["email"]
        user.save(update_fields=["first_name", "last_name", "email"])

        chauffeur.taxi_license_number = data["taxi_license_number"]
        chauffeur.save(update_fields=["taxi_license_number"])

        return Response(serializer.data)


class MobileVehicleCreateView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        chauffeur = get_current_chauffeur(request.user)

        serializer = MobileVehicleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        # if not serializer.is_valid():
        #     logger.warning("Vehicle creation validation failed: %s", serializer.errors)
        #     return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        data = serializer.validated_data

        license_plate = data["license_plate"]

        if ChauffeurVehicle.objects.filter(
            chauffeur=chauffeur,
            license_plate__iexact=license_plate,
            is_active=True,
        ).exists():
            raise ValidationError({"detail": "Dit kenteken is al toegevoegd."})

        with transaction.atomic():
            has_vehicle = ChauffeurVehicle.objects.filter(
                chauffeur=chauffeur,
                is_active=True,
            ).exists()

            make_current = data.get("is_current", False) or not has_vehicle

            if make_current:
                ChauffeurVehicle.objects.filter(
                    chauffeur=chauffeur,
                    is_active=True,
                ).update(is_current=False)

            vehicle = ChauffeurVehicle.objects.create(
                chauffeur=chauffeur,
                license_plate=license_plate,
                nickname=data.get("nickname", ""),
                vehicle_type=data.get("vehicle_type", VehicleType.AUTO),
                is_current=make_current,
                is_active=True,
            )

        return Response(
            MobileVehicleSerializer(vehicle).data,
            status=status.HTTP_201_CREATED,
        )


class MobileVehicleSetCurrentView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, vehicle_id):
        chauffeur = get_current_chauffeur(request.user)

        try:
            vehicle = ChauffeurVehicle.objects.get(
                id=vehicle_id,
                chauffeur=chauffeur,
                is_active=True,
            )
        except ChauffeurVehicle.DoesNotExist:
            raise ValidationError({"detail": "Voertuig niet gevonden."})

        with transaction.atomic():
            ChauffeurVehicle.objects.filter(
                chauffeur=chauffeur,
                is_active=True,
            ).update(is_current=False)

            vehicle.is_current = True
            vehicle.save(update_fields=["is_current"])

        return Response(MobileVehicleSerializer(vehicle).data)


class MobileVehicleDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, vehicle_id):
        chauffeur = get_current_chauffeur(request.user)

        vehicles = ChauffeurVehicle.objects.filter(
            chauffeur=chauffeur,
            is_active=True,
        )

        try:
            vehicle = vehicles.get(id=vehicle_id)
        except ChauffeurVehicle.DoesNotExist:
            raise ValidationError({"detail": "Voertuig niet gevonden."})

        if vehicles.count() <= 1:
            raise ValidationError({"detail": "U moet minimaal één voertuig behouden."})

        was_current = vehicle.is_current

        with transaction.atomic():
            vehicle.is_active = False
            vehicle.is_current = False
            vehicle.save(update_fields=["is_active", "is_current"])

            if was_current:
                replacement = (
                    ChauffeurVehicle.objects.filter(
                        chauffeur=chauffeur,
                        is_active=True,
                    )
                    .exclude(id=vehicle_id)
                    .order_by("id")
                    .first()
                )

                if replacement:
                    replacement.is_current = True
                    replacement.save(update_fields=["is_current"])

        return Response(status=204)
