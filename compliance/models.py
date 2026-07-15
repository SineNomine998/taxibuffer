from django.db import models


# Create your models here.
class PrivacyPolicy(models.Model):
    version = models.CharField(max_length=30, unique=True)
    title = models.CharField(max_length=200, default="Privacyverklaring TaxiBuffer")
    body_nl = models.TextField()
    effective_from = models.DateTimeField()
    is_active = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-effective_from", "-created_at"]

    def __str__(self):
        return f"{self.title} v{self.version}"


class PrivacyPolicyAcceptance(models.Model):
    chauffeur = models.ForeignKey(
        "accounts.Chauffeur",
        on_delete=models.CASCADE,
        related_name="privacy_acceptances",
    )
    policy = models.ForeignKey(
        PrivacyPolicy,
        on_delete=models.PROTECT,
        related_name="acceptances",
    )

    accepted_at = models.DateTimeField(auto_now_add=True)
    user_agent = models.TextField(blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["chauffeur", "policy"],
                name="unique_chauffeur_policy_acceptance",
            )
        ]

    def __str__(self):
        return f"{self.chauffeur_id} accepted {self.policy.version}"


class TermsOfUse(models.Model):
    version = models.CharField(max_length=30, unique=True)
    title = models.CharField(
        max_length=200,
        default="Gebruiksvoorwaarden TaxiBuffer",
    )
    body_nl = models.TextField()
    effective_from = models.DateTimeField()
    is_active = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-effective_from"]

    def __str__(self):
        return f"{self.title} v{self.version}"


class TermsOfUseAcceptance(models.Model):
    chauffeur = models.ForeignKey(
        "accounts.Chauffeur",
        on_delete=models.CASCADE,
        related_name="terms_acceptances",
    )
    terms = models.ForeignKey(
        TermsOfUse,
        on_delete=models.PROTECT,
        related_name="acceptances",
    )

    accepted_at = models.DateTimeField(auto_now_add=True)
    user_agent = models.TextField(blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["chauffeur", "terms"],
                name="unique_chauffeur_terms_acceptance",
            )
        ]

    def __str__(self):
        return f"{self.chauffeur_id} accepted terms {self.terms.version}"
