import logging
import pytz

from datetime import timedelta
from django.db import transaction
from django.utils import timezone
from django.contrib.auth import get_user_model, authenticate
from django.contrib.auth.forms import PasswordResetForm
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError, NotFound
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
    serialize_queue,
    serialize_notification,
    serialize_waiting_entry,
)
from accounts.models import Chauffeur, ChauffeurVehicle, VehicleType
from queueing.models import TaxiQueue, QueueEntry, QueueNotification
from queueing.services import QueueService
from queueing.constants import ACTIVE_QUEUE_STATUSES
from geofence.services import point_in_buffer, make_point_from_lat_lng
from queueing.views import _build_unique_username
from compliance.models import PrivacyPolicyAcceptance
from compliance.services import (
    accept_active_privacy_policy,
    get_active_privacy_policy,
    has_accepted_active_privacy_policy,
)
from compliance.permissions import HasAcceptedPrivacyPolicy
from mobile_api.models import MobilePushToken
from mobile_api.push import send_location_lost_push

logger = logging.getLogger(__name__)

User = get_user_model()


def get_current_chauffeur(user):
    chauffeur = getattr(user, "chauffeur", None)
    if chauffeur is None:
        raise PermissionDenied("Geen chauffeurprofiel gevonden.")
    return chauffeur


def parse_lat_lng(data):
    lat = data.get("lat")
    lng = data.get("lng")

    if lat is None or lng is None:
        raise ValidationError({"detail": "Locatiegegevens ontbreken."})

    try:
        return float(lat), float(lng)
    except (TypeError, ValueError):
        raise ValidationError({"detail": "Ongeldige locatiegegevens."})


class MobileBootstrapView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        chauffeur = get_current_chauffeur(request.user)
        policy = get_active_privacy_policy()

        privacy_required = not has_accepted_active_privacy_policy(chauffeur)

        return Response(
            {
                "privacy_policy_required": privacy_required,
                "current_privacy_policy_version": policy.version if policy else None,
            }
        )


class MobilePrivacyPolicyView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        chauffeur = get_current_chauffeur(request.user)
        policy = get_active_privacy_policy()

        if policy is None:
            return Response(
                {"detail": "Geen actieve privacyverklaring gevonden."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        accepted = PrivacyPolicyAcceptance.objects.filter(
            chauffeur=chauffeur,
            policy=policy,
        ).exists()

        return Response(
            {
                "id": policy.id,
                "version": policy.version,
                "title": policy.title,
                "body_nl": policy.body_nl,
                "effective_from": policy.effective_from,
                "accepted": accepted,
            }
        )


class PublicPrivacyPolicyView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        policy = get_active_privacy_policy()

        if policy is None:
            return Response(
                {"detail": "Geen actieve privacyverklaring gevonden."},
                status=status.HTTP_404_NOT_FOUND,
            )

        return Response(
            {
                "version": policy.version,
                "title": policy.title,
                "body_nl": policy.body_nl,
                "effective_from": policy.effective_from,
            }
        )


class MobileAcceptPrivacyPolicyView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        chauffeur = get_current_chauffeur(request.user)
        policy = get_active_privacy_policy()

        if policy is None:
            return Response(
                {"detail": "Geen actieve privacyverklaring gevonden."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        version = request.data.get("version")

        if version != policy.version:
            return Response(
                {
                    "detail": "Privacyverklaring versie komt niet overeen.",
                    "current_version": policy.version,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        acceptance = accept_active_privacy_policy(
            chauffeur=chauffeur,
            request=request,
        )

        return Response(
            {
                "success": True,
                "version": policy.version,
                "accepted_at": acceptance.accepted_at,
            }
        )


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

                accept_active_privacy_policy(chauffeur=chauffeur, request=request)

        except Exception:
            logger.exception("Mobile signup failed")
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
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

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
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

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
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

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
                if QueueEntry.objects.filter(
                    chauffeur=chauffeur, status__in=ACTIVE_QUEUE_STATUSES
                ):
                    raise ValidationError(
                        {
                            "detail": "Het is niet toegestaan om van voertuig te wisselen tijdens een actieve wachtrij deelname."
                        }
                    )
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
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request, vehicle_id):
        chauffeur = get_current_chauffeur(request.user)

        if QueueEntry.objects.filter(
            chauffeur=chauffeur, status__in=ACTIVE_QUEUE_STATUSES
        ):
            raise ValidationError(
                {
                    "detail": "Het is niet toegestaan om van voertuig te wisselen tijdens een actieve wachtrij deelname."
                }
            )

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


class MobileVehicleDetailView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

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

        if was_current and QueueEntry.objects.filter(
            chauffeur=chauffeur, status__in=ACTIVE_QUEUE_STATUSES
        ):
            raise ValidationError(
                {
                    "detail": "Het is niet toegestaan om het voertuig te verwijderen waarmee u zich heeft aangemeld voor een actieve wachtrij."
                }
            )

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

    def patch(self, request, vehicle_id):
        chauffeur = get_current_chauffeur(request.user)

        try:
            vehicle = ChauffeurVehicle.objects.get(
                id=vehicle_id,
                chauffeur=chauffeur,
                is_active=True,
            )
        except ChauffeurVehicle.DoesNotExist:
            raise ValidationError({"detail": "Voertuig niet gevonden."})

        serializer = MobileVehicleSerializer(
            data=request.data,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        license_plate = normalize_license_plate(data["license_plate"])

        if (
            ChauffeurVehicle.objects.filter(
                chauffeur=chauffeur,
                license_plate__iexact=license_plate,
                is_active=True,
            )
            .exclude(id=vehicle.id)
            .exists()
        ):
            raise ValidationError({"detail": "Dit kenteken is al toegevoegd."})

        if vehicle.is_current and QueueEntry.objects.filter(
            chauffeur=chauffeur, status__in=ACTIVE_QUEUE_STATUSES
        ):
            raise ValidationError(
                {
                    "detail": "Het is niet toegestaan om het voertuig te bewerken waarmee u zich heeft aangemeld voor een actieve wachtrij."
                }
            )

        with transaction.atomic():
            vehicle.license_plate = license_plate
            vehicle.nickname = data["nickname"]
            vehicle.vehicle_type = data["vehicle_type"]
            vehicle.save(update_fields=["license_plate", "nickname", "vehicle_type"])

        return Response(
            MobileVehicleSerializer(vehicle).data,
            status=status.HTTP_200_OK,
        )


class MobileQueueListView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def get(self, request):
        chauffeur = get_current_chauffeur(request.user)

        current_vehicle = chauffeur.get_current_vehicle()
        if not current_vehicle:
            return Response(
                {
                    "detail": "U heeft nog geen huidig voertuig. Voeg eerst een voertuig toe."
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        active_entry = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=ACTIVE_QUEUE_STATUSES,
            )
            .select_related("queue")
            .order_by("-created_at")
            .first()
        )

        is_waiting = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur, status=QueueEntry.Status.WAITING
            )
            .select_related("queue")
            .order_by("-created_at")
            .first()
        )

        queues = (
            TaxiQueue.objects.filter(active=True)
            .select_related("buffer_zone", "pickup_zone")
            .order_by("pickup_zone__created_at")
        )

        return Response(
            {
                "active_entry_uuid": str(active_entry.uuid) if active_entry else None,
                "already_in_queue": active_entry is not None,
                "actively_waiting": is_waiting is not None,
                "queues": [serialize_queue(queue, request) for queue in queues],
            }
        )


class MobileValidateLocationView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request, queue_id):
        queue = (
            TaxiQueue.objects.select_related("buffer_zone")
            .filter(id=queue_id, active=True)
            .first()
        )

        if queue is None:
            raise NotFound("Deze wachtrij is momenteel gesloten.")

        lat, lng = parse_lat_lng(request.data)

        buffer_zone = getattr(queue, "buffer_zone", None)
        if not buffer_zone:
            return Response(
                {
                    "is_valid": True,
                    "inside_buffer": True,
                    "message": "Geen bufferzone ingesteld.",
                }
            )

        inside = point_in_buffer(buffer_zone, lat, lng, inclusive=True)

        if not inside:
            return Response(
                {
                    "is_valid": False,
                    "inside_buffer": False,
                    "error_message": (
                        f"U bevindt zich nog niet in de buurt van bufferzone "
                        f"{buffer_zone.name}."
                    ),
                },
                status=status.HTTP_200_OK,
            )

        return Response(
            {
                "is_valid": True,
                "inside_buffer": True,
                "message": "Locatie goedgekeurd.",
            }
        )


class MobileJoinQueueView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request, queue_id):
        chauffeur = get_current_chauffeur(request.user)

        queue = (
            TaxiQueue.objects.select_related("buffer_zone")
            .filter(id=queue_id, active=True)
            .first()
        )

        if queue is None:
            raise NotFound("Deze wachtrij is momenteel gesloten.")

        current_vehicle = chauffeur.get_current_vehicle()
        if not current_vehicle:
            logger.warning(
                "Mobile join failed: no current vehicle user=%s", request.user.email
            )
            return Response(
                {"detail": "U kunt alleen aanmelden met een huidig voertuig."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing_entry = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=ACTIVE_QUEUE_STATUSES,
            )
            .order_by("-created_at")
            .first()
        )

        logger.info(
            "Mobile join attempt user=%s queue_id=%s lat=%s lng=%s",
            request.user.email,
            queue_id,
            request.data.get("lat"),
            request.data.get("lng"),
        )

        if existing_entry:
            return Response(
                {
                    "success": True,
                    "already_in_queue": True,
                    "entry_uuid": str(existing_entry.uuid),
                    "queue_id": existing_entry.queue_id,
                    "status": existing_entry.status,
                    "position": existing_entry.get_queue_position(),
                    "detail": (
                        "U bent al opgeroepen. Ga naar de ophaallocatie."
                        if existing_entry.status == QueueEntry.Status.NOTIFIED
                        else "U staat al in een wachtrij."
                    ),
                },
                status=status.HTTP_200_OK,
            )

        has_push_token = MobilePushToken.objects.filter(
            chauffeur=chauffeur,
            active=True,
        ).exists()

        if not has_push_token:
            logger.warning(
                "Mobile join failed: no active push token user=%s",
                request.user.email,
            )
            return Response(
                {
                    "detail": (
                        "Meldingen zijn verplicht om deel te nemen aan de wachtrij. "
                        "Schakel meldingen in en probeer opnieuw."
                    ),
                    "code": "notifications_required",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        lat, lng = parse_lat_lng(request.data)
        signup_point = make_point_from_lat_lng(lat, lng, srid=4326)

        buffer_zone = getattr(queue, "buffer_zone", None)
        if buffer_zone:
            inside = point_in_buffer(buffer_zone, lat, lng, inclusive=True)
            if not inside:
                return Response(
                    {
                        "detail": (
                            f"U bevindt zich nog niet in de buurt van bufferzone "
                            f"{buffer_zone.name}."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        queue_service = QueueService()
        success, message, entry_uuid = queue_service.add_chauffeur_to_queue(
            chauffeur=chauffeur,
            queue=queue,
            signup_location=signup_point,
        )

        if not success:
            logger.warning(
                "Mobile join failed: QueueService success=False user=%s queue_id=%s message=%s entry_uuid=%s",
                request.user.email,
                queue_id,
                message,
                entry_uuid,
            )

            if message == "Notification missed." and entry_uuid:
                missed_entry = QueueEntry.objects.filter(uuid=entry_uuid).first()

                if missed_entry:
                    return Response(
                        {
                            "success": True,
                            "already_in_queue": True,
                            "entry_uuid": str(missed_entry.uuid),
                            "queue_id": missed_entry.queue_id,
                            "status": missed_entry.status,
                            "position": missed_entry.get_queue_position(),
                            "detail": (
                                "U bent al opgeroepen. Ga naar de wachtrijstatuspagina."
                                if missed_entry.status == QueueEntry.Status.NOTIFIED
                                else "U staat al in een wachtrij."
                            ),
                        },
                        status=status.HTTP_200_OK,
                    )

                return Response(
                    {
                        "detail": "Er is iets misgegaan. Open de wachtrijstatuspagina of probeer opnieuw.",
                        "code": "queue_state_unknown",
                    },
                    status=status.HTTP_409_CONFLICT,
                )

            return Response(
                {
                    "detail": message or "Kon niet aanmelden.",
                    "entry_uuid": str(entry_uuid) if entry_uuid else None,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        entry = (
            QueueEntry.objects.filter(
                queue=queue,
                chauffeur=chauffeur,
                status__in=ACTIVE_QUEUE_STATUSES,
            )
            .order_by("-created_at")
            .first()
        )

        if entry is None:
            return Response(
                {"detail": "Aanmelding gelukt, maar wachtrij-item niet gevonden."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {
                "success": True,
                "entry_uuid": str(entry.uuid),
                "queue_id": queue.id,
                "status": entry.status,
                "position": entry.get_queue_position(),
            },
            status=status.HTTP_201_CREATED,
        )


class MobilePushTokenView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request):
        chauffeur = get_current_chauffeur(request.user)

        token = request.data.get("token")
        platform = request.data.get("platform", "")

        if not token:
            return Response(
                {"detail": "Push token ontbreekt."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        MobilePushToken.objects.update_or_create(
            token=token,
            defaults={
                "chauffeur": chauffeur,
                "platform": platform,
                "active": True,
            },
        )

        return Response({"success": True}, status=status.HTTP_200_OK)


class MobileQueueStatusView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def get(self, request):
        chauffeur = get_current_chauffeur(request.user)

        entry = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=ACTIVE_QUEUE_STATUSES,
            )
            .select_related("queue", "chauffeur__user")
            .order_by("-created_at")
            .first()
        )

        if entry is None:
            return Response(
                {
                    "in_queue": False,
                    "entry": None,
                    "waiting_people": [],
                }
            )

        queue = entry.queue

        lat = request.query_params.get("lat")
        lng = request.query_params.get("lng")

        if lat and lng:
            try:
                lat = float(lat)
                lng = float(lng)
                buffer_zone = getattr(queue, "buffer_zone", None)

                if buffer_zone and not point_in_buffer(buffer_zone, lat, lng):
                    entry.status = QueueEntry.Status.LEFT_ZONE
                    entry.dequeued_at = timezone.now()
                    entry.save(update_fields=["status", "dequeued_at"])

                    return Response(
                        {
                            "in_queue": False,
                            "dequeued": True,
                            "dequeue_reason": "left_zone",
                            "detail": "U bent uit de bufferzone gegaan.",
                        }
                    )
            except (TypeError, ValueError):
                pass

        waiting_entries = (
            queue.get_waiting_entries()
            .select_related("chauffeur__user")
            .order_by("created_at")
        )

        pending_notification = (
            QueueNotification.objects.filter(
                queue_entry=entry,
                response=QueueNotification.ResponseType.PENDING,
            )
            .order_by("-notification_time")
            .first()
        )

        notification_data = serialize_notification(pending_notification)

        return Response(
            {
                "in_queue": True,
                "entry": {
                    "uuid": str(entry.uuid),
                    "queue_id": queue.id,
                    "queue_name": str(queue),
                    "status": entry.status,
                    "status_display": entry.get_status_display(),
                    "position": entry.get_queue_position(),
                    "total_waiting": waiting_entries.count(),
                    "license_plate": entry.display_license_plate,
                    "created_at": (
                        entry.created_at.isoformat() if entry.created_at else None
                    ),
                },
                "has_notification": pending_notification is not None,
                "notification": notification_data,
                "sequence_number": (
                    notification_data["sequence_number"] if notification_data else None
                ),
                "last_updated": timezone.now().isoformat(),
                "waiting_people": [
                    serialize_waiting_entry(waiting_entry, chauffeur.id)
                    for waiting_entry in waiting_entries
                ],
            }
        )


class MobileLeaveQueueView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request):
        chauffeur = get_current_chauffeur(request.user)

        entry = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=ACTIVE_QUEUE_STATUSES,
            )
            .order_by("-created_at")
            .first()
        )

        if entry is None:
            return Response(
                {"detail": "U staat momenteel niet in een actieve wachtrij."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        entry.status = QueueEntry.Status.LEFT_ZONE
        entry.dequeued_at = timezone.now()
        entry.save(update_fields=["status", "dequeued_at"])

        return Response(
            {
                "success": True,
                "message": "U heeft de wachtrij verlaten.",
            }
        )


class MobileNotificationResponseView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def post(self, request):
        chauffeur = get_current_chauffeur(request.user)

        notification_id = request.data.get("notification_id")
        response_type = request.data.get("response")

        if not notification_id or not response_type:
            raise ValidationError({"detail": "Ontbrekende gegevens."})

        if response_type not in ["accepted", "declined"]:
            raise ValidationError({"detail": "Ongeldig antwoord."})

        notification = (
            QueueNotification.objects.select_related("queue_entry")
            .filter(
                id=notification_id,
                queue_entry__chauffeur=chauffeur,
            )
            .first()
        )

        if notification is None:
            raise NotFound("Oproep niet gevonden.")

        if notification.response != QueueNotification.ResponseType.PENDING:
            raise ValidationError({"detail": "Deze oproep is al beantwoord."})

        if response_type == "accepted":
            notification.respond(QueueNotification.ResponseType.ACCEPTED)
            message = "Oproep geaccepteerd."
        # else:
        #     notification.respond(QueueNotification.ResponseType.DECLINED)
        #     message = "Oproep geweigerd."

        return Response(
            {
                "success": True,
                "message": message,
            }
        )


class MobileSequenceHistoryView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    def get(self, request):
        chauffeur = get_current_chauffeur(request.user)

        europe = pytz.timezone("Europe/Amsterdam")
        now_local = timezone.now().astimezone(europe)
        today_start_local = now_local.replace(
            hour=0,
            minute=0,
            second=0,
            microsecond=0,
        )
        today_start_utc = today_start_local.astimezone(pytz.UTC)

        notifications = (
            QueueNotification.objects.filter(
                queue_entry__chauffeur=chauffeur,
                notification_time__gte=today_start_utc,
            )
            .select_related("queue_entry", "queue_entry__queue")
            .order_by("-notification_time")
        )

        items = []

        for notification in notifications:
            local_time = (
                notification.notification_time.astimezone(europe)
                if notification.notification_time
                else None
            )

            items.append(
                {
                    "id": notification.id,
                    "sequence_number": notification.sequence_number,
                    "response": notification.response,
                    "entry_status": notification.queue_entry.status,
                    "notification_time": (
                        notification.notification_time.isoformat()
                        if notification.notification_time
                        else None
                    ),
                    "local_time": local_time.strftime("%H:%M") if local_time else None,
                    "queue_id": notification.queue_entry.queue_id,
                    "queue_name": str(notification.queue_entry.queue),
                    "entry_uuid": str(notification.queue_entry.uuid),
                }
            )

        return Response(
            {
                "date": now_local.strftime("%d-%m-%Y"),
                "items": items,
            }
        )


class MobileQueueLocationReportView(APIView):
    permission_classes = [IsAuthenticated, HasAcceptedPrivacyPolicy]

    # TODO: timeout = 4 mins?
    GRACE_PERIOD = timedelta(minutes=4)

    def post(self, request, entry_uuid):
        chauffeur = get_current_chauffeur(request.user)

        entry = (
            QueueEntry.objects.select_related("queue", "queue__buffer_zone")
            .filter(uuid=entry_uuid, chauffeur=chauffeur)
            .first()
        )

        if entry is None:
            raise NotFound("Wachtrij-item niet gevonden.")

        if entry.status != QueueEntry.Status.WAITING:
            return Response(
                {
                    "success": True,
                    "action": "ignored",
                    "status": entry.status,
                }
            )

        lat = request.data.get("lat")
        lng = request.data.get("lng")

        if lat is None or lng is None:
            return self._handle_location_unavailable(entry)

        try:
            lat = float(lat)
            lng = float(lng)
        except ValueError:
            raise ValidationError({"detail": "Ongeldige locatiegegevens."})

        now = timezone.now()

        entry.last_location_at = now
        entry.last_location_lat = lat
        entry.last_location_lng = lng

        buffer_zone = getattr(entry.queue, "buffer_zone", None)

        if buffer_zone is None:
            entry.save(
                update_fields=[
                    "last_location_at",
                    "last_location_lat",
                    "last_location_lng",
                ]
            )
            return Response({"success": True, "action": "no_buffer"})

        inside = point_in_buffer(buffer_zone, lat, lng, inclusive=True)

        if inside:
            entry.location_lost_at = None
            entry.location_warning_sent_at = None
            entry.save(
                update_fields=[
                    "last_location_at",
                    "last_location_lat",
                    "last_location_lng",
                    "location_lost_at",
                    "location_warning_sent_at",
                ]
            )

            return Response(
                {
                    "success": True,
                    "action": "inside_buffer",
                    "dequeued": False,
                }
            )

        if entry.location_lost_at is None:
            entry.location_lost_at = now
            entry.location_warning_sent_at = now
            entry.save(
                update_fields=[
                    "last_location_at",
                    "last_location_lat",
                    "last_location_lng",
                    "location_lost_at",
                    "location_warning_sent_at",
                ]
            )

            transaction.on_commit(
                lambda entry_id=entry.id: send_location_lost_push(entry_id)
            )

            return Response(
                {
                    "success": True,
                    "action": "outside_warning",
                    "dequeued": False,
                    "grace_seconds": int(self.GRACE_PERIOD.total_seconds()),
                    "message": (
                        "U bent buiten de bufferzone. Keer binnen 4 minuten terug "
                        "om in de wachtrij te blijven."
                    ),
                }
            )

        deadline = entry.location_lost_at + self.GRACE_PERIOD

        if now >= deadline:
            entry.status = QueueEntry.Status.LEFT_ZONE
            entry.dequeued_at = now
            entry.save(
                update_fields=[
                    "last_location_at",
                    "last_location_lat",
                    "last_location_lng",
                    "status",
                    "dequeued_at",
                ]
            )

            return Response(
                {
                    "success": True,
                    "action": "dequeued_left_zone",
                    "dequeued": True,
                    "message": "U bent te lang buiten de bufferzone gebleven en daarom uit de wachtrij verwijderd.",
                }
            )

        remaining = int((deadline - now).total_seconds())

        entry.save(
            update_fields=[
                "last_location_at",
                "last_location_lat",
                "last_location_lng",
            ]
        )

        return Response(
            {
                "success": True,
                "action": "outside_grace",
                "dequeued": False,
                "remaining_seconds": remaining,
                "message": "U bent buiten de bufferzone. Keer terug om in de wachtrij te blijven.",
            }
        )

    def _handle_location_unavailable(self, entry):
        now = timezone.now()

        if entry.status != QueueEntry.Status.WAITING:
            return Response(
                {
                    "success": True,
                    "action": "ignored",
                    "status": entry.status,
                }
            )

        if entry.location_lost_at is None:
            entry.location_lost_at = now
            entry.location_warning_sent_at = now
            entry.save(
                update_fields=[
                    "location_lost_at",
                    "location_warning_sent_at",
                ]
            )

            transaction.on_commit(
                lambda entry_id=entry.id: send_location_lost_push(entry_id)
            )

            return Response(
                {
                    "success": True,
                    "action": "location_unavailable_warning",
                    "dequeued": False,
                    "grace_seconds": int(self.GRACE_PERIOD.total_seconds()),
                    "message": (
                        "Locatie is uitgeschakeld of niet beschikbaar. "
                        "Zet locatie binnen 4 minuten weer aan om in de wachtrij te blijven."
                    ),
                }
            )

        deadline = entry.location_lost_at + self.GRACE_PERIOD

        if now >= deadline:
            entry.status = QueueEntry.Status.LEFT_ZONE
            entry.dequeued_at = now
            entry.save(
                update_fields=[
                    "status",
                    "dequeued_at",
                ]
            )

            return Response(
                {
                    "success": True,
                    "action": "dequeued_location_unavailable",
                    "dequeued": True,
                    "message": (
                        "U bent uit de wachtrij verwijderd omdat uw locatie te lang "
                        "niet beschikbaar was."
                    ),
                }
            )

        remaining = int((deadline - now).total_seconds())

        return Response(
            {
                "success": True,
                "action": "location_unavailable_grace",
                "dequeued": False,
                "remaining_seconds": remaining,
                "message": (
                    "Locatie is nog steeds niet beschikbaar. Zet locatie aan om in de wachtrij te blijven."
                ),
            }
        )
