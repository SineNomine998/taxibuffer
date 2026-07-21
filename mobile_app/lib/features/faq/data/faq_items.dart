import '../models/faq_item.dart';

const faqItems = <FaqItem>[
  FaqItem(
    category: 'Algemeen',
    question: 'Wat is TaxiBuffer?',
    answer:
        'TaxiBuffer is een wachtrij-app voor chauffeurs. De app helpt om de volgorde eerlijk te beheren en geeft aan wanneer u mag doorrijden naar de ophaallocatie.',
  ),
  FaqItem(
    category: 'Wachtrij',
    question: 'Hoe meld ik mij aan voor een wachtrij?',
    answer:
        'Ga naar de locatiepagina, kies de juiste wachtrij en tik op Aanmelden. U moet zich binnen de bufferzone bevinden en locatie- en pushmeldingen moeten aanstaan.',
  ),
  FaqItem(
    category: 'Wachtrij',
    question: 'Kan ik mij aanmelden als ik niet in de bufferzone ben?',
    answer:
        'Nee. Om de wachtrij eerlijk te houden, kunt u zich alleen aanmelden wanneer u fysiek binnen de bufferzone bent.',
  ),
  FaqItem(
    category: 'Locatie',
    question: 'Waarom gebruikt de app mijn locatie?',
    answer:
        'De app gebruikt uw locatie om te controleren of u in de bufferzone bent terwijl u in de wachtrij staat. Dit voorkomt dat chauffeurs buiten de zone wachten terwijl ze toch een plek in de wachtrij houden.',
  ),
  FaqItem(
    category: 'Locatie',
    question: 'Wat gebeurt er als ik de bufferzone verlaat?',
    answer:
        'U krijgt een waarschuwing en een korte tijd om terug te keren. Als u te lang buiten de bufferzone blijft, kunt u automatisch uit de wachtrij worden verwijderd.',
  ),
  FaqItem(
    category: 'Meldingen',
    question: 'Waarom moet ik pushmeldingen toestaan?',
    answer:
        'Pushmeldingen zijn nodig om u direct te waarschuwen wanneer u aan de beurt bent of wanneer er iets mis is met uw locatiecontrole.',
  ),
  FaqItem(
    category: 'Meldingen',
    question: 'Ik ontvang geen meldingen. Wat kan ik doen?',
    answer:
        'Controleer in uw telefooninstellingen of meldingen voor TaxiBuffer zijn toegestaan. Ga daarna in de app naar Instellingen en gebruik Pushmeldingen testen.',
  ),
  FaqItem(
    category: 'Wachtrij',
    question: 'Wat betekent “U bent opgeroepen”?',
    answer:
        'Dit betekent dat u aan de beurt bent. Rij door naar de ophaallocatie en volg de aanwijzingen van de medewerkers op locatie.',
  ),
  FaqItem(
    category: 'Account',
    question: 'Kan ik meerdere voertuigen gebruiken?',
    answer:
        'Ja. U kunt meerdere voertuigen toevoegen aan uw account. Zorg ervoor dat het actieve voertuig overeenkomt met het voertuig waarmee u zich aanmeldt.',
  ),
  FaqItem(
    category: 'Account',
    question: 'Mijn kenteken klopt niet. Wat moet ik doen?',
    answer:
        'Ga naar uw accountpagina en pas uw voertuiggegevens aan. Het juiste kenteken is belangrijk voor controle op locatie.',
  ),
];
