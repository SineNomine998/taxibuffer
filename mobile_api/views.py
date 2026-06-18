from django.db import transaction
from django.contrib.auth import get_user_model
from django.contrib.auth import authenticate
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenRefreshView

from mobile_api.serializers import MobileLoginSerializer, MobileSignUpSerializer, normalize_license_plate
from accounts.models import Chauffeur, ChauffeurVehicle, VehicleType
from queueing.views import _build_unique_username

User = get_user_model()


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
    permission_classes = [IsAuthenticated]

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


class MobileMeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user

        return Response(
            {
                "id": user.id,
                "username": user.get_username(),
                "first_name": user.first_name,
                "last_name": user.last_name,
                "email": user.email,
                "is_active": user.is_active,
                "taxi_license_number": user.chauffeur.taxi_license_number,
                "current_vehicle": normalize_license_plate(
                    user.chauffeur.current_license_plate
                ),
            }
        )


class MobileSignUpView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = MobileSignUpSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
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
                    data["rtx_number"],
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
                    taxi_license_number=data["rtx_number"],
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
