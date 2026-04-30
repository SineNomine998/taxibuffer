from django.contrib import admin

from .models import BufferZone, PickupZone


@admin.register(BufferZone)
class BufferZoneAdmin(admin.ModelAdmin):
    list_display = ("name", "active", "created_at", "updated_at")
    list_filter = ("active",)
    search_fields = ("name",)


@admin.register(PickupZone)
class PickupZoneAdmin(admin.ModelAdmin):
    list_display = ("name", "address", "active", "created_at", "updated_at")
    list_filter = ("active",)
    search_fields = ("name", "address")
    fields = (
        "name",
        "address",
        "image_url",
        "total_sensors",
        "num_of_occupied_sensors",
        "active",
    )
