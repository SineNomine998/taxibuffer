from django.db import models


# Create your models here.
class MobilePushToken(models.Model):
    chauffeur = models.ForeignKey("accounts.Chauffeur", on_delete=models.CASCADE)
    token = models.TextField(unique=True)
    platform = models.CharField(max_length=20, blank=True)
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
