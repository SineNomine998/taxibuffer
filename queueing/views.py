from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator
from django.views import View
from django.urls import reverse
from django.contrib.gis.geos import Point
from django.utils import timezone
from django.utils.safestring import mark_safe
from django.db import transaction
import json
from django.conf import settings
from django.http import FileResponse
from django.contrib.auth import login
import re
import os
import logging

from accounts.models import Chauffeur, ChauffeurVehicle, User, VehicleType
from .models import TaxiQueue, QueueEntry, QueueNotification
from .services import QueueService
from geofence.services import point_in_buffer, make_point_from_lat_lng

logger = logging.getLogger(__name__)


def _build_unique_username(first_name, last_name, rtx_number):
    base = f"{first_name}.{last_name}".strip(".").lower()
    base = re.sub(r"[^a-z0-9._-]", "", base.replace(" ", "_"))
    if not base:
        base = f"chauffeur_{rtx_number.lower()}"
    candidate = base
    counter = 1
    while User.objects.filter(username=candidate).exists():
        candidate = f"{base}_{counter}"
        counter += 1
    return candidate


def _is_admin_request(request, data):
    if data.get("license_plate") == "SINENOMINE":
        return True

    email = (data.get("email") or "").strip().lower()
    if "@admin.com" in email:
        return True

    user_email = (getattr(getattr(request, "user", None), "email", "") or "").strip().lower()
    return "@admin.com" in user_email


def _get_authenticated_chauffeur(request):
    chauffeur_id = request.session.get("authenticated_chauffeur_id")
    if not chauffeur_id:
        return None
    try:
        return Chauffeur.objects.select_related("user").get(id=chauffeur_id)
    except Chauffeur.DoesNotExist:
        return None


class InfoPagesView(View):
    """Serves informational pages regarding this taxi buffer system TaxiBuffer."""

    def get(self, request):
        """Display info page."""
        step = int(request.session.get("info_step", 1))
        print("CURRENT INFO STEP:", step)
        context = {"step": step}
        return render(request, "queueing/info_pages.html", context)

    def post(self, request):
        """Handle navigation between info pages."""
        step = int(request.session.get("info_step", 1))

        if step < 2:
            step += 1
            request.session["info_step"] = step
            return redirect(reverse("queueing:info_pages"))
        else:
            request.session.pop("info_step", None)
            return redirect("queueing:chauffeur_login")


class ChauffeurLoginView(View):
    """Handle chauffeur authentication (Step 1)"""

    def get(self, request):
        """Display login form."""
        context = {
            "show_access_denied": request.GET.get("access_denied") == "true",
            "form_data": request.session.get("login_form_data", {}),
        }
        return render(request, "queueing/chauffeur_login.html", context)

    def post(self, request):
        """Process login form."""
        email = request.POST.get("email", "").strip().lower()
        password = request.POST.get("password", "")

        request.session["login_form_data"] = {
            "email": email,
        }

        if not email or not password:
            messages.error(request, "Emailadres en wachtwoord zijn verplicht.")
            return redirect("queueing:chauffeur_login")

        # Keep admin testing bypass intact.
        if email.upper() == "SINENOMINE" and password.upper() == "TEST":
            try:
                test_vehicle = ChauffeurVehicle.objects.select_related("chauffeur").get(
                    license_plate="SINENOMINE", is_current=True, is_active=True
                )
                chauffeur = test_vehicle.chauffeur
            except ChauffeurVehicle.DoesNotExist:
                user = User.objects.create_user(
                    username="test_chauffeur", is_chauffeur=True
                )
                chauffeur = Chauffeur.objects.create(
                    user=user,
                    taxi_license_number="TEST",
                    location=None,
                )
                ChauffeurVehicle.objects.create(
                    chauffeur=chauffeur,
                    license_plate="SINENOMINE",
                    nickname="Test voertuig",
                    vehicle_type=VehicleType.AUTO,
                    is_current=True,
                    is_active=True,
                )
            request.session["authenticated_chauffeur_id"] = chauffeur.id
            request.session["form_data"] = {
                "license_plate": chauffeur.current_license_plate,
                "taxi_license_number": chauffeur.taxi_license_number,
            }
            return redirect("queueing:location_selection")

        account_user = (
            User.objects.filter(
                email__iexact=email,
                is_chauffeur=True,
            )
            .select_related("chauffeur")
            .first()
        )
        if account_user and password and account_user.check_password(password):
            if hasattr(account_user, "chauffeur"):
                chauffeur = account_user.chauffeur
                request.session["authenticated_chauffeur_id"] = chauffeur.id
                request.session["form_data"] = {
                    "license_plate": chauffeur.current_license_plate,
                    "taxi_license_number": chauffeur.taxi_license_number,
                }
                login(request, account_user)
                return redirect("queueing:location_selection")

        messages.error(request, "Ongeldig emailadres of wachtwoord.")
        return redirect("queueing:chauffeur_login")

    def validate_license_plate_format(self, license_plate):
        """Validate license plate format (basic validation)."""
        return True

        # TODO: Double check the Dutch license plate formats: 1-ABC-23, AB-123-C, etc.
        # Apparently, there are quite a few valid formats (excluding these ones), so for now we don't check the format at all
        # patterns = [
        #     r"^[A-Z]{2}-\d{2}-\d{2}$",  # XX-99-99
        #     r"^\d{2}-\d{2}-[A-Z]{2}$",  # 99-99-XX
        #     r"^[A-Z]{2}-\d{2}-[A-Z]{2}$",  # XX-99-XX
        #     r"^\d{2}-[A-Z]{2}-\d{2}$",  # 99-XX-99
        #     r"^[A-Z]{2}-[A-Z]{2}-\d{2}$",  # XX-XX-99
        #     r"^\d{2}-[A-Z]{2}-[A-Z]{2}$",  # 99-XX-XX
        #     r"^[A-Z]{1}-\d{3}-[A-Z]{2}$",  # X-999-XX
        #     r"^[A-Z]{2}-\d{3}-[A-Z]{1}$",  # XX-999-X
        #     r"^\d{3}-[A-Z]{2}-[A-Z]{1}$",  # 999-XX-X
        #     r"^\d{3}-[A-Z]{1}-[A-Z]{2}$",  # 999-X-XX
        #     r"^\d{1,2}-[A-Z]{2,3}-\d{1,2}$",  # 1-ABC-23
        #     r"^\d{3}-[A-Z]{2}-\d{1,2}$",  # 123-AB-1
        #     r"^[A-Z]{3}-\d{2}-\d{1,2}$",  # ABC-12-3
        # ]
        # return any(re.match(pattern, license_plate) for pattern in patterns)

    def validate_taxi_license_format(self, taxi_license):
        """Validate taxi license format.

        Allowed formats:
            - DDDD      (4 digits)
            - DDDDD     (5 digits)
            - DDDD-XD   (4 digits, a dash, one letter, one digit)
        """
        pattern = r"^(?:\d{4}|\d{5}|\d{4}-[A-Za-z]\d)$"
        return bool(re.fullmatch(pattern, taxi_license))


class LocationSelectionInfoView(View):
    def get(self, request):
        return render(request, "queueing/location_selection_info.html")


class SignUpStep1View(View):
    """Signup step 1: collect profile basics."""

    template_name = "queueing/sign_up1.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        context = {
            "form_data": {
                "first_name": flow.get("first_name", ""),
                "last_name": flow.get("last_name", ""),
                "email": flow.get("email", ""),
                "rtx_number": flow.get("rtx_number", ""),
            }
        }
        return render(request, self.template_name, context)

    def post(self, request):
        first_name = request.POST.get("first_name", "").strip()
        last_name = request.POST.get("last_name", "").strip()
        email = request.POST.get("email", "").strip().lower()
        rtx_number = request.POST.get("rtx_number", "").strip().upper()

        if not all([first_name, last_name, email, rtx_number]):
            messages.error(request, "Vul alle verplichte velden in.")
            return redirect("queueing:sign_up1")

        if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
            messages.error(request, "Vul een geldig emailadres in.")
            return redirect("queueing:sign_up1")

        if User.objects.filter(email__iexact=email).exists():
            messages.error(request, "Dit emailadres is al in gebruik.")
            return redirect("queueing:sign_up1")

        flow = request.session.get("signup_flow", {})
        flow["first_name"] = first_name
        flow["last_name"] = last_name
        flow["email"] = email
        flow["rtx_number"] = rtx_number
        flow.setdefault("vehicles", [])
        request.session["signup_flow"] = flow

        return redirect("queueing:sign_up2")


class SignUpPasswordView(View):
    """Signup step 2: set account password."""

    template_name = "queueing/sign_up2_password.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")
        return render(request, self.template_name)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        password = request.POST.get("password", "")
        password_repeat = request.POST.get("password_repeat", "")

        if not password or not password_repeat:
            messages.error(request, "Vul beide wachtwoordvelden in.")
            return redirect("queueing:sign_up2")

        if password != password_repeat:
            messages.error(request, "Wachtwoorden komen niet overeen.")
            return redirect("queueing:sign_up2")

        if len(password) < 8:
            messages.error(request, "Kies een wachtwoord van minimaal 8 tekens.")
            return redirect("queueing:sign_up2")

        flow["raw_password"] = password
        request.session["signup_flow"] = flow

        return redirect("queueing:sign_up3")


class SignUpVehicleView(View):
    """Signup step 3: select current vehicle and finish."""

    template_name = "queueing/sign_up3_vehicle.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        vehicles = flow.get("vehicles", [])
        current_index = flow.get("current_vehicle_index")
        if current_index is None and vehicles:
            current_index = 0
            flow["current_vehicle_index"] = 0
            request.session["signup_flow"] = flow

        current_vehicle = None
        other_vehicles = []
        if (
            vehicles
            and current_index is not None
            and 0 <= current_index < len(vehicles)
        ):
            current_vehicle = vehicles[current_index]
            other_vehicles = [
                {"vehicle": v, "index": i}
                for i, v in enumerate(vehicles)
                if i != current_index
            ]

        context = {
            "current_vehicle": current_vehicle,
            "other_vehicles": other_vehicles,
            "has_vehicles": len(vehicles) > 0,
        }
        return render(request, self.template_name, context)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        action = request.POST.get("action", "finish")
        vehicles = flow.get("vehicles", [])

        if action == "set_current":
            index = request.POST.get("vehicle_index", "")
            try:
                index = int(index)
            except (ValueError, TypeError):
                messages.error(request, "Kon huidig voertuig niet instellen.")
                return redirect("queueing:sign_up3")

            if 0 <= index < len(vehicles):
                flow["current_vehicle_index"] = index
                request.session["signup_flow"] = flow
            return redirect("queueing:sign_up3")

        if action == "remove_vehicle":
            index = request.POST.get("vehicle_index", "")
            try:
                index = int(index)
            except (ValueError, TypeError):
                messages.error(request, "Kon voertuig niet verwijderen.")
                return redirect("queueing:sign_up3")

            if 0 <= index < len(vehicles):
                vehicles.pop(index)
                flow["vehicles"] = vehicles

                current_index = flow.get("current_vehicle_index")
                if not vehicles:
                    flow["current_vehicle_index"] = None
                elif current_index is None:
                    flow["current_vehicle_index"] = 0
                elif current_index == index:
                    flow["current_vehicle_index"] = 0
                elif current_index > index:
                    flow["current_vehicle_index"] = current_index - 1

                request.session["signup_flow"] = flow
            return redirect("queueing:sign_up3")

        if not vehicles:
            messages.error(request, "Voeg minimaal 1 voertuig toe om verder te gaan.")
            return redirect("queueing:sign_up3")

        current_index = flow.get("current_vehicle_index")
        if current_index is None or current_index >= len(vehicles):
            flow["current_vehicle_index"] = 0

        first_name = flow.get("first_name", "").strip()
        last_name = flow.get("last_name", "").strip()
        email = flow.get("email", "").strip().lower()
        rtx_number = flow.get("rtx_number", "").strip().upper()
        raw_password = flow.get("raw_password", "")

        if not all([first_name, last_name, email, rtx_number, raw_password]):
            messages.error(request, "Onvolledige accountgegevens. Start opnieuw.")
            return redirect("queueing:sign_up1")

        try:
            with transaction.atomic():
                # TODO:
                # This piece of code that is commented out does the following:
                #   - It checks existing chauffeurs with the same RTX number
                #   - If found one, it shows an error message and redirects to login page instead of signup
                # It was commented out because it caused issues when chauffeurs forgot their passwords.

                # existing_chauffeur = (
                #     Chauffeur.objects.filter(taxi_license_number=rtx_number)
                #     .select_related("user")
                #     .first()
                # )
                # if existing_chauffeur:
                #     messages.error(
                #         request,
                #         "Er bestaat al een account met dit RTX-nummer. Gebruik inloggen.",
                #     )
                #     return redirect("queueing:chauffeur_login")

                username = _build_unique_username(first_name, last_name, rtx_number)
                user = User.objects.create_user(
                    username=username,
                    email=email,
                    password=raw_password,
                    first_name=first_name,
                    last_name=last_name,
                    is_chauffeur=True,
                )

                current_vehicle_index = int(flow.get("current_vehicle_index", 0))
                current_vehicle = vehicles[current_vehicle_index]

                chauffeur = Chauffeur.objects.create(
                    user=user,
                    taxi_license_number=rtx_number,
                    location=None,
                )

                for idx, vehicle in enumerate(vehicles):
                    ChauffeurVehicle.objects.create(
                        chauffeur=chauffeur,
                        license_plate=vehicle["license_plate"],
                        nickname=vehicle["nickname"],
                        vehicle_type=vehicle.get("vehicle_type", VehicleType.AUTO),
                        is_current=(idx == current_vehicle_index),
                        is_active=True,
                    )

            # Log in the user FIRST
            login(request, user)
            
            # Then set session variables and save explicitly
            request.session["authenticated_chauffeur_id"] = chauffeur.id
            request.session["form_data"] = {
                "license_plate": chauffeur.current_license_plate,
                "taxi_license_number": chauffeur.taxi_license_number,
            }
            request.session.pop("signup_flow", None)
            request.session.modified = True
            
            messages.success(request, "Account aangemaakt. Welkom bij TAXIBUFFER.")
            return redirect("queueing:account")
        except Exception as e:
            logger.exception("Could not create signup account: %s", e)
            messages.error(
                request, "Account kon niet worden aangemaakt. Probeer opnieuw."
            )
            return redirect("queueing:sign_up3")


class SignUpAddVehicleView(View):
    """Sub-step from step 3 for adding one vehicle."""

    template_name = "queueing/sign_up_vehicle_add.html"

    def get(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")
        return render(request, self.template_name)

    def post(self, request):
        flow = request.session.get("signup_flow", {})
        if not flow.get("first_name"):
            return redirect("queueing:sign_up1")

        license_plate = request.POST.get("license_plate", "").strip().upper()
        nickname = request.POST.get("nickname", "").strip()
        vehicle_type = request.POST.get("vehicle_type", VehicleType.AUTO)
        set_as_current = request.POST.get("set_as_current") == "on"

        if not license_plate or not nickname:
            messages.error(request, "Vul kenteken en bijnaam in.")
            return redirect("queueing:sign_up_vehicle_add")

        if len(license_plate) > 20 or len(nickname) > 60:
            messages.error(request, "Kenteken of bijnaam is te lang.")
            return redirect("queueing:sign_up_vehicle_add")

        if vehicle_type not in [VehicleType.AUTO, VehicleType.BUSJE]:
            messages.error(request, "Kies een geldig voertuigtype.")
            return redirect("queueing:sign_up_vehicle_add")

        vehicles = flow.get("vehicles", [])
        duplicate = any(v["license_plate"].upper() == license_plate for v in vehicles)
        if duplicate:
            messages.error(request, "Dit kenteken is al toegevoegd.")
            return redirect("queueing:sign_up_vehicle_add")

        vehicles.append(
            {
                "license_plate": license_plate,
                "nickname": nickname,
                "vehicle_type": vehicle_type,
            }
        )
        flow["vehicles"] = vehicles

        if set_as_current or len(vehicles) == 1:
            flow["current_vehicle_index"] = len(vehicles) - 1

        request.session["signup_flow"] = flow
        return redirect("queueing:sign_up3")


class AccountView(View):
    """Account dashboard for chauffeurs and vehicle management."""

    template_name = "queueing/account.html"

    def get(self, request):
        chauffeur = _get_authenticated_chauffeur(request)
        if not chauffeur:
            messages.error(request, "Log eerst in om uw account te bekijken.")
            return redirect("queueing:chauffeur_login")

        vehicles = list(
            chauffeur.vehicles.filter(is_active=True).order_by(
                "-is_current", "nickname", "id"
            )
        )
        current_vehicle = next((v for v in vehicles if v.is_current), None)

        context = {
            "chauffeur": chauffeur,
            "account_user": chauffeur.user,
            "current_vehicle": current_vehicle,
            "vehicles": vehicles,
            "vehicle_type_choices": VehicleType.choices,
            "active_tab": "account",
        }
        return render(request, self.template_name, context)

    def post(self, request):
        chauffeur = _get_authenticated_chauffeur(request)
        if not chauffeur:
            messages.error(request, "Log eerst in om uw account te beheren.")
            return redirect("queueing:chauffeur_login")

        action = request.POST.get("action", "")

        if action == "update_profile":
            first_name = request.POST.get("first_name", "").strip()
            last_name = request.POST.get("last_name", "").strip()
            email = request.POST.get("email", "").strip().lower()
            taxi_license_number = request.POST.get("taxi_license_number", "").strip().upper()

            if not all([first_name, last_name, email, taxi_license_number]):
                messages.error(request, "Vul naam, e-mail en RTX-nummer volledig in.")
                return redirect("queueing:account")

            if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
                messages.error(request, "Vul een geldig e-mailadres in.")
                return redirect("queueing:account")

            # TODO:
            # This part is commented out to make sure chauffeurs are allowed to create multiple accounts
            # with the same credentials if they ever forget their password.

            # duplicate_email = User.objects.filter(email__iexact=email).exclude(
            #     id=chauffeur.user_id
            # )
            # if duplicate_email.exists():
            #     messages.error(request, "Dit e-mailadres is al in gebruik.")
            #     return redirect("queueing:account")

            # Allowed formats: DDDD, DDDDD, DDDD-XD
            if not re.fullmatch(r"^(?:\d{4}|\d{5}|\d{4}-[A-Za-z]\d)$", taxi_license_number):
                messages.error(
                    request,
                    "RTX-nummer heeft een ongeldig formaat. Gebruik 4 of 5 cijfers, of DDDD-XD.",
                )
                return redirect("queueing:account")

            # TODO:
            # This part is commented out to make sure chauffeurs are allowed to create multiple accounts
            # with the same credentials if they ever forget their password.
            # It checks for duplicate RTX numbers and prevents saving if found.

            # duplicate_rtx = Chauffeur.objects.filter(
            #     taxi_license_number__iexact=taxi_license_number
            # ).exclude(id=chauffeur.id)
            # if duplicate_rtx.exists():
            #     messages.error(request, "Dit RTX-nummer is al in gebruik.")
            #     return redirect("queueing:account")

            with transaction.atomic():
                chauffeur.user.first_name = first_name
                chauffeur.user.last_name = last_name
                chauffeur.user.email = email
                chauffeur.user.save(update_fields=["first_name", "last_name", "email"])

                chauffeur.taxi_license_number = taxi_license_number
                chauffeur.save(update_fields=["taxi_license_number", "updated_at"])

            form_data = request.session.get("form_data", {})
            form_data["taxi_license_number"] = chauffeur.taxi_license_number
            request.session["form_data"] = form_data

            messages.success(request, "Profielgegevens bijgewerkt.")
            return redirect("queueing:account")

        if action == "set_current":
            vehicle_id = request.POST.get("vehicle_id")
            vehicle = ChauffeurVehicle.objects.filter(
                id=vehicle_id, chauffeur=chauffeur, is_active=True
            ).first()
            if not vehicle:
                messages.error(request, "Voertuig niet gevonden.")
                return redirect("queueing:account")
            
            has_active_queue_entry = QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
            ).exists()
            if has_active_queue_entry:
                messages.error(
                    request,
                    "U kunt uw huidige voertuig niet veranderen terwijl u in de wachtrij staat. Verlaat eerst de wachtrij.",
                )
                return redirect("queueing:account")

            with transaction.atomic():
                ChauffeurVehicle.objects.filter(
                    chauffeur=chauffeur, is_active=True
                ).update(is_current=False)
                vehicle.is_current = True
                vehicle.save(update_fields=["is_current", "updated_at"])

            request.session["form_data"] = {
                "license_plate": chauffeur.current_license_plate,
                "taxi_license_number": chauffeur.taxi_license_number,
            }
            messages.success(request, "Huidig voertuig bijgewerkt.")
            return redirect("queueing:account")

        if action == "add_vehicle":
            license_plate = request.POST.get("license_plate", "").strip().upper()
            nickname = request.POST.get("nickname", "").strip()
            vehicle_type = request.POST.get("vehicle_type", VehicleType.AUTO)
            set_as_current = request.POST.get("set_as_current") == "on"

            if not license_plate or not nickname:
                messages.error(request, "Vul kenteken en bijnaam in.")
                return redirect("queueing:account")

            existing = ChauffeurVehicle.objects.filter(
                chauffeur=chauffeur, license_plate__iexact=license_plate, is_active=True
            ).exists()
            if existing:
                messages.error(request, "Dit kenteken bestaat al in uw account.")
                return redirect("queueing:account")

            if vehicle_type not in [VehicleType.AUTO, VehicleType.BUSJE]:
                messages.error(request, "Kies een geldig voertuigtype.")
                return redirect("queueing:account")

            with transaction.atomic():
                if (
                    set_as_current
                    or not chauffeur.vehicles.filter(is_active=True).exists()
                ):
                    ChauffeurVehicle.objects.filter(
                        chauffeur=chauffeur, is_active=True
                    ).update(is_current=False)
                new_vehicle = ChauffeurVehicle.objects.create(
                    chauffeur=chauffeur,
                    license_plate=license_plate,
                    nickname=nickname,
                    vehicle_type=vehicle_type,
                    is_current=(
                        set_as_current
                        or not chauffeur.vehicles.filter(is_active=True).exists()
                    ),
                )

            messages.success(request, "Voertuig toegevoegd.")
            return redirect("queueing:account")

        if action == "remove_vehicle":
            vehicle_id = request.POST.get("vehicle_id")
            vehicle = ChauffeurVehicle.objects.filter(
                id=vehicle_id, chauffeur=chauffeur, is_active=True
            ).first()
            if not vehicle:
                messages.error(request, "Voertuig niet gevonden.")
                return redirect("queueing:account")

            if vehicle.is_current:
                has_active_queue_entry = QueueEntry.objects.filter(
                    chauffeur=chauffeur,
                    status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
                ).exists()
                if has_active_queue_entry:
                    messages.error(
                        request,
                        "U kunt uw huidige voertuig niet verwijderen terwijl u in de wachtrij staat. Verlaat eerst de wachtrij.",
                    )
                    return redirect("queueing:account")

            with transaction.atomic():
                was_current = vehicle.is_current
                # vehicle.delete()  # Don't delete for data integrity, just mark as inactive
                vehicle.is_active = False
                vehicle.is_current = False
                vehicle.save(update_fields=["is_active", "is_current", "updated_at"])

                if was_current:
                    replacement = (
                        chauffeur.vehicles.filter(is_active=True).order_by("id").first()
                    )
                    if replacement:
                        replacement.is_current = True
                        replacement.save(update_fields=["is_current", "updated_at"])

            messages.success(request, "Voertuig verwijderd.")
            return redirect("queueing:account")

        messages.error(request, "Onbekende actie.")
        return redirect("queueing:account")


class QueueStatusView(View):
    """Display queue status for a specific chauffeur."""

    def get(self, request, entry_uuid):
        """Display queue status page."""
        try:
            # Get the specific queue entry by UUID
            entry = get_object_or_404(QueueEntry, uuid=entry_uuid)
            queue = entry.queue
            chauffeur = entry.chauffeur

            waiting_entries = (
                queue.get_waiting_entries()
                .select_related("chauffeur__user")
                .order_by("created_at")
            )

            waiting_people = [
                {
                    "first_name": waiting_entry.chauffeur.user.first_name,
                    "license_plate": waiting_entry.display_license_plate,
                    "is_current_chauffeur": waiting_entry.chauffeur_id == chauffeur.id,
                }
                for waiting_entry in waiting_entries
            ]

            context = {
                "queue": queue,
                "chauffeur": chauffeur,
                "entry": entry,
                "active_tab": "queue",
                "waiting_people": waiting_people,
                "vapid_public_key": settings.WEBPUSH_SETTINGS["VAPID_PUBLIC_KEY"],
            }
            return render(request, "queueing/queue_status.html", context)

        except Exception as e:
            messages.error(request, f"Invalid queue entry: {str(e)}")
            return redirect("queueing:chauffeur_login")


class QueueOverviewView(View):
    """Display the full queue page for the chauffeur's active queue."""

    def get(self, request):
        chauffeur = _get_authenticated_chauffeur(request)
        if not chauffeur:
            messages.error(request, "Log eerst in om uw wachtrij te bekijken.")
            return redirect("queueing:chauffeur_login")

        active_entry = (
            QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
            )
            .order_by("-created_at")
            .first()
        )

        if active_entry:
            queue = active_entry.queue
            waiting_entries = (
                queue.get_waiting_entries()
                .select_related("chauffeur__user")
                .order_by("created_at")
            )

            waiting_people = [
                {
                    "first_name": waiting_entry.chauffeur.user.first_name,
                    "license_plate": waiting_entry.display_license_plate,
                    "is_current_chauffeur": waiting_entry.chauffeur_id == chauffeur.id,
                }
                for waiting_entry in waiting_entries
            ]

            context = {
                "queue": queue,
                "chauffeur": chauffeur,
                "entry": active_entry,
                "active_tab": "queue",
                "waiting_people": waiting_people,
            }
            return render(request, "queueing/queue.html", context)

        messages.info(request, "U staat momenteel in geen enkele wachtrij.")
        return redirect("queueing:location_selection")


class QueueStatusAPIView(View):
    """API endpoint for live queue status updates."""

    def get(self, request, entry_uuid):
        """Return JSON with current queue status."""
        try:
            entry = QueueEntry.objects.get(uuid=entry_uuid)
            queue = entry.queue
            # TODO! THIS PART IS RELATED TO AUTOMATIC DEQUEUING; MIGHT NOT BE WORKING OPTIMALLY
            # Check for automatic dequeuing based on location
            lat = request.GET.get('lat')
            lng = request.GET.get('lng')
            if lat and lng:
                try:
                    lat = float(lat)
                    lng = float(lng)
                    buffer_zone = getattr(queue, 'buffer_zone', None)
                    if buffer_zone and not point_in_buffer(buffer_zone, lat, lng) and not _is_admin_request(request, data={}):
                        # Chauffeur has left the buffer zone, dequeue automatically
                        if entry.status in [QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED]:
                            entry.status = QueueEntry.Status.LEFT_ZONE
                            entry.dequeued_at = timezone.now()
                            entry.save()
                            logger.info(f"Auto-dequeued chauffeur {entry.chauffeur} for leaving buffer zone.")
                except (ValueError, TypeError):
                    pass  # Invalid lat/lng, ignore

            # Get queue position and waiting count
            position = entry.get_queue_position()
            waiting_entries = queue.get_waiting_entries().select_related(
                "chauffeur__user"
            ).order_by("created_at")
            total_waiting = waiting_entries.count()


            # Get pending notifications
            pending_notifications = QueueNotification.objects.filter(
                queue_entry=entry, response=QueueNotification.ResponseType.PENDING
            ).order_by("-notification_time")

            has_pending_notification = pending_notifications.exists()
            notification_data = None

            if has_pending_notification:
                notification = pending_notifications.first()
                notification_data = {
                    "id": notification.id,
                    "notification_time": notification.notification_time.isoformat(),
                    "sequence_number": notification.sequence_number,
                }

            waiting_people = [
                {
                    "first_name": waiting_entry.chauffeur.user.first_name,
                    "license_plate": waiting_entry.display_license_plate,
                    "is_current_chauffeur": waiting_entry.chauffeur_id == entry.chauffeur_id,
                    "position": waiting_entry.get_queue_position(),
                }
                for waiting_entry in waiting_entries
            ]

            return JsonResponse(
                {
                    "success": True,
                    "status": entry.get_status_display(),
                    "status_code": entry.status,
                    "position": position,
                    "total_waiting": total_waiting,
                    "has_notification": has_pending_notification,
                    "notification": notification_data,
                    "sequence_number": (
                        notification_data.get("sequence_number")
                        if notification_data
                        else None
                    ),
                    "last_updated": timezone.now().isoformat(),
                    "waiting_people": waiting_people,
                }
            )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


class LeaveQueueBeforeNotificationAPIView(View):
    """Allow chauffeurs to leave the queue voluntarily before receiving any notification."""

    @method_decorator(csrf_exempt)
    def dispatch(self, *args, **kwargs):
        return super().dispatch(*args, **kwargs)

    def post(self, request, entry_uuid):
        try:
            entry = get_object_or_404(QueueEntry, uuid=entry_uuid)

            # Check if entry is active (i.e. waiting or notified)
            if entry.status in [QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED]:
                entry.status = QueueEntry.Status.LEFT_ZONE
                entry.dequeued_at = timezone.now()
                entry.save()

                return JsonResponse(
                    {"success": True, "message": "Successfully left the queue."}
                )
            else:
                return JsonResponse(
                    {"success": False, "error": "Entry is no longer active."}
                )

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=400)


class LocationSelectionView(View):
    """Handle location selection (Step 2)"""

    def get(self, request):
        """Display location selection."""
        chauffeur_uuid = request.session.get("authenticated_chauffeur_id")
        if not chauffeur_uuid:
            logger.warning("Please authenticate first.")
            return redirect("queueing:chauffeur_login")

        try:
            chauffeur = Chauffeur.objects.get(id=chauffeur_uuid)
            current_vehicle = chauffeur.get_current_vehicle()
            if not current_vehicle:
                messages.error(
                    request,
                    "U heeft nog geen huidig voertuig. Voeg een voertuig toe in uw account.",
                )
                return redirect("queueing:account")

            # Check if chauffeur is already in an active queue
            active_entry = QueueEntry.objects.filter(
                chauffeur=chauffeur,
                status__in=[QueueEntry.Status.WAITING, QueueEntry.Status.NOTIFIED],
            ).first()

            if active_entry:
                # If they're already in a queue, redirect them to that queue's status page
                return redirect("queueing:queue_status", entry_uuid=active_entry.uuid)

        except Chauffeur.DoesNotExist:
            logger.warning("Invalid session. Please authenticate again.")
            return redirect("queueing:chauffeur_login")

        active_queues = TaxiQueue.objects.filter(active=True).select_related(
            "buffer_zone", "pickup_zone"
        )

        for queue in active_queues:
            queue.waiting_count = queue.get_waiting_entries().count()

        form_data = request.session.get("form_data", {})
        form_data["license_plate"] = current_vehicle.license_plate
        request.session["form_data"] = form_data
        context = {
            "chauffeur": chauffeur,
            "queues": active_queues,
            "form_data": form_data,
            "active_tab": "locations",
        }
        return render(request, "queueing/location_selection.html", context)

    def post(self, request):
        """Process location selection and join queue."""
        chauffeur_id = request.session.get("authenticated_chauffeur_id")
        if not chauffeur_id:
            logger.warning("Please authenticate first.")
            return redirect("queueing:chauffeur_login")

        selected_queue_id = request.POST.get("selected_queue_id")
        if not selected_queue_id:
            logger.warning("Please select a pickup location.")
            return redirect("queueing:location_selection")

        try:
            chauffeur = Chauffeur.objects.get(id=chauffeur_id)
            queue = TaxiQueue.objects.get(id=selected_queue_id, active=True)
        except (Chauffeur.DoesNotExist, TaxiQueue.DoesNotExist):
            logger.warning("Invalid selection. Please try again.")
            return redirect("queueing:location_selection")

        current_vehicle = chauffeur.get_current_vehicle()
        if not current_vehicle:
            messages.error(
                request,
                "U kunt alleen aanmelden met een huidig voertuig. Stel eerst een huidig voertuig in.",
            )
            return redirect("queueing:account")

        latitude = request.POST.get("signup_lat")
        longitude = request.POST.get("signup_lng")
        signup_point = None

        if latitude and longitude:
            try:
                latitude = float(latitude)
                longitude = float(longitude)
                signup_point = make_point_from_lat_lng(latitude, longitude, srid=4326)
            except ValueError:
                logger.warning("Invalid latitude/longitude values.")
                messages.error(
                    request, "Invalid location coordinates.", extra_tags="location"
                )
                return redirect("queueing:location_selection")
        else:
            logger.warning("Missing latitude/longitude values.")
            messages.error(
                request, "Location coordinates are required.", extra_tags="location"
            )
            return redirect("queueing:location_selection")

        if signup_point is None and getattr(chauffeur, "location", None):
            signup_point = chauffeur.location

        if signup_point is None:
            logger.warning("Could not determine signup location.")
            messages.error(
                request,
                "Kon uw locatie niet bepalen. Schakel locatievoorziening in en probeer opnieuw.",
                extra_tags="location",
            )
            return redirect("queueing:location_selection")

        admin_license_plate = (current_vehicle.license_plate or "").upper()
        buffer_zone = getattr(queue, "buffer_zone", None)
        if buffer_zone and getattr(buffer_zone, "zone", None):
            try:
                if "point_in_buffer" in globals() and callable(point_in_buffer):
                    inside = point_in_buffer(
                        buffer_zone, signup_point.y, signup_point.x, inclusive=True
                    )
                else:
                    inside = buffer_zone.zone.buffer(0.00005).intersects(signup_point)
            except Exception as e:
                logger.exception("Geofence spatial check failed: %s", e)
                inside = False

            # Allow admin override for testing or admin email addresses.
            if not inside and not _is_admin_request(request, data={"license_plate": admin_license_plate}):
                messages.error(
                    request,
                    mark_safe(
                        f"U bevindt zich nog niet in de buurt van bufferzone <strong>{buffer_zone.name}</strong> en kunt u dus nog niet aanmelden voor de wachtrij."
                    ),
                    extra_tags="geofence",
                )
                return redirect("queueing:location_selection")
        else:
            logger.warning(
                "Queue %s has no buffer zone defined; allowing join", queue.id
            )

        try:
            queue_service = QueueService()
            success, message, entry_uuid = queue_service.add_chauffeur_to_queue(
                chauffeur=chauffeur, queue=queue, signup_location=signup_point
            )

            if success:
                entry = (
                    QueueEntry.objects.filter(
                        queue=queue,
                        chauffeur=chauffeur,
                        status__in=[
                            QueueEntry.Status.WAITING,
                            QueueEntry.Status.NOTIFIED,
                        ],
                    )
                    .order_by("-created_at")
                    .first()
                )

                if entry:
                    logger.debug(message)
                    return redirect("queueing:queue_status", entry_uuid=entry.uuid)
                else:
                    logger.warning("Failed to retrieve queue entry.")
                    messages.error(
                        request,
                        "Er is iets misgegaan. Neem contact op met de beheerder.",
                    )
                    return redirect("queueing:location_selection")
            else:
                logger.debug(message)
                messages.error(request, message or "Kon niet aanmelden :(")
                return redirect("queueing:queue_status", entry_uuid=entry_uuid)

        except Exception as e:
            logger.error(f"Failed to join queue: {str(e)}")
            messages.error(
                request,
                "Er is iets misgegaan bij het aanmelden. Probeer later opnieuw.",
            )
            return redirect("queueing:location_selection")


@method_decorator(csrf_exempt, name="dispatch")
class NotificationResponseView(View):
    """Handle chauffeur responses to notifications."""

    def post(self, request):
        """Process notification response."""
        try:
            data = json.loads(request.body)
            notification_id = data.get("notification_id")
            response_type = data.get("response")

            if not all([notification_id, response_type]):
                return JsonResponse(
                    {"success": False, "error": "Missing required fields"}, status=400
                )

            if response_type not in ["accepted", "declined"]:
                return JsonResponse(
                    {"success": False, "error": "Invalid response type"}, status=400
                )

            notification = get_object_or_404(QueueNotification, id=notification_id)

            if notification.response != QueueNotification.ResponseType.PENDING:
                return JsonResponse(
                    {
                        "success": False,
                        "error": "Notification has already been responded to",
                    },
                    status=400,
                )

            if response_type == "accepted":
                notification.respond(QueueNotification.ResponseType.ACCEPTED)
                message = "Drive safely :)"

            return JsonResponse({"success": True, "message": message})

        except Exception as e:
            return JsonResponse({"success": False, "error": str(e)}, status=500)


# Manual trigger view for testing/admin purposes
class ManualTriggerView(View):
    """Manual trigger for testing - simulates sensor detection of available slots."""

    def get(self, request, queue_id):
        """Display manual trigger form."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)

        context = {
            "queue": queue,
            "waiting_count": queue.get_waiting_entries().count(),
        }
        return render(request, "queueing/manual_trigger.html", context)

    def post(self, request, queue_id):
        """Process manual trigger."""
        queue = get_object_or_404(TaxiQueue, id=queue_id, active=True)
        slots_available = int(request.POST.get("slots_available", 1))
        send_push = request.POST.get("send_push") == "1"

        try:
            queue_service = QueueService()
            notification_options = {
                "send_push": send_push,
            }

            notified_count = queue_service.notify_next_chauffeurs(
                queue, slots_available, notification_options
            )

            if notified_count > 0:
                print(f"Notified {notified_count} chauffeur(s) to proceed.")
            else:
                print("No chauffeurs in queue to notify.")

        except Exception as e:
            print(f"Error: {str(e)}")

        return redirect("queueing:manual_trigger", queue_id=queue_id)

    def validate_taxi_license_format(self, taxi_license):
        """Validate taxi license format (basic validation)."""

        # Basic format: letters and numbers, 3-20 characters
        return re.match(r"^[A-Z0-9]{3,20}$", taxi_license) is not None


def service_worker(request):
    """Serve service worker from root URL"""
    # Path to the service worker file in the static folder
    sw_path = os.path.join(
        settings.BASE_DIR, "queueing", "static", "queueing", "js", "sw.js"
    )

    # Serve the file with the correct mime type
    response = FileResponse(open(sw_path, "rb"), content_type="application/javascript")

    # Add cache control headers
    response["Service-Worker-Allowed"] = "/"
    response["Cache-Control"] = "no-cache"

    return response
