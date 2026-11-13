/// Les textes légaux, séparés de leur mise en page : ils se relisent, se
/// comparent et se testent plus facilement qu'un long widget.
///
/// Règle d'écriture : chaque phrase doit pouvoir être vérifiée dans le code.
/// Si le comportement change (durée de conservation, ce qui est visible), le
/// texte change en même temps, et [legalVersion] aussi — c'est cette version
/// que l'API enregistre à l'inscription.
library;

/// Version affichée dans l'app et acceptée à l'inscription.
/// À faire correspondre à TERMS_VERSION côté API.
const legalVersion = '1.0 — novembre 2026';

/// Adresse de contact publiée dans les deux textes.
/// Surchargeable au build : --dart-define=CONTACT_EMAIL=equipe@ton-domaine.org
const contactEmail = String.fromEnvironment(
  'CONTACT_EMAIL',
  defaultValue: 'equipe@ding.app',
);

class LegalSection {
  const LegalSection(this.title, {this.paragraphs = const [], this.bullets = const []});

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
}

class LegalDoc {
  const LegalDoc({
    required this.title,
    required this.subtitle,
    required this.sections,
  });

  final String title;
  final String subtitle;
  final List<LegalSection> sections;
}

const termsDoc = LegalDoc(
  title: 'Conditions d’utilisation',
  subtitle:
      'Ce que Ding fait, ce qu’il ne fait pas, et ce que tu t’engages à ne pas '
      'en faire. Si une phrase te paraît floue, écris-nous avant de créer ton '
      'compte.',
  sections: [
    LegalSection(
      '1. Ce qu’est Ding',
      paragraphs: [
        'Ding est un service gratuit de mise en relation par réciprocité, '
            'destiné à la communauté d’un campus. Tu désignes en secret des '
            'personnes qui t’intriguent. Si l’une d’elles te désigne aussi, '
            'et que vous vous trouvez à moins de 150 mètres, vos deux '
            'téléphones sonnent.',
        'Ding n’est ni un réseau social, ni un site de rencontre à profils '
            'publics, ni un service d’urgence.',
      ],
    ),
    LegalSection(
      '2. Ton compte',
      paragraphs: [
        'Pour créer un compte, tu déclares sur l’honneur remplir ces '
            'conditions :',
      ],
      bullets: [
        'Avoir 18 ans révolus.',
        'Utiliser une adresse email qui t’appartient, et un seul compte par '
            'personne.',
        'Donner un prénom réel : c’est le seul nom que les autres voient, '
            'dans l’annuaire du campus.',
        'Garder ton mot de passe pour toi. Toute action faite depuis ton '
            'compte est réputée être la tienne.',
      ],
    ),
    LegalSection(
      '3. Ce que les autres voient de toi',
      paragraphs: [
        'Tu apparais dans l’annuaire sous ton prénom, avec ta faculté et ta '
            'promotion si tu les as renseignées. Tu peux à tout moment '
            'disparaître de l’annuaire depuis ton profil : tes choix restent '
            'enregistrés, mais plus personne ne peut te désigner.',
        'Tes choix sont secrets. Aucun écran, aucune réponse du serveur, '
            'aucune notification ne dit à quiconque que tu l’as choisi. La '
            'réciprocité est calculée sur le serveur, jamais dans le '
            'téléphone.',
      ],
    ),
    LegalSection(
      '4. Ce qui est interdit',
      bullets: [
        'Harceler, insulter, menacer, ou continuer à écrire à quelqu’un '
            'après un blocage.',
        'Te faire passer pour une autre personne, ou créer un profil pour '
            'quelqu’un qui ne l’a pas demandé.',
        'Envoyer ou publier des contenus sexuels, haineux, ou qui portent '
            'atteinte à la dignité d’autrui.',
        'Diffuser des informations personnelles sur quelqu’un sans son '
            'accord.',
        'Utiliser Ding pour du démarchage, de la publicité, ou pour de '
            'l’automatisation (robot, script).',
        'Contourner un blocage ou une suspension en créant un autre compte.',
      ],
    ),
    LegalSection(
      '5. Signalements et suspension',
      paragraphs: [
        'Chaque profil peut être signalé depuis l’annuaire, pour un motif '
            'précis. Les signalements sont lus par l’équipe du campus, pas '
            'par une machine.',
        'Un signalement n’est pas une sanction : l’équipe peut le classer '
            'sans suite. Elle peut aussi suspendre un compte, sans préavis si '
            'la sécurité de quelqu’un est en jeu. La suspension coupe la '
            'connexion et retire le profil de l’annuaire.',
        'L’identité de la personne qui signale n’apparaît jamais dans '
            'l’outil de modération : on ne peut pas te reprocher d’avoir '
            'signalé.',
        'Tu peux contester une suspension en écrivant à l’adresse de '
            'contact, en bas de cette page. On te répond.',
      ],
    ),
    LegalSection(
      '6. Ce que Ding ne promet pas',
      bullets: [
        'Que quelqu’un te choisisse. Une alarme ne se commande pas.',
        'Une position exacte. La localisation dépend du téléphone, du ciel et '
            'de la batterie ; un croisement peut être manqué si l’un des deux '
            'téléphones n’a pas de réseau.',
        'De fonctionner quand l’app a été quittée. Aujourd’hui l’alarme sonne '
            'écran éteint, mais pas après une fermeture complète de l’app : '
            'c’est une limite connue, pas un oubli.',
        'Un service d’urgence. En cas de danger, appelle les secours, pas '
            'Ding.',
      ],
    ),
    LegalSection(
      '7. Gratuité',
      paragraphs: [
        'Ding est gratuit, sans publicité et sans traceur publicitaire. Si '
            'cela devait changer, ces conditions changeraient avant.',
      ],
    ),
    LegalSection(
      '8. Fin du compte',
      paragraphs: [
        'Tu peux supprimer ton compte à tout moment depuis ton profil : '
            'l’effacement est immédiat et définitif. De notre côté, un compte '
            'qui enfreint ces conditions peut être suspendu ou supprimé.',
      ],
    ),
    LegalSection(
      '9. Modifications',
      paragraphs: [
        'Chaque version de ce texte est datée et publiée dans l’app. Un '
            'changement important est signalé à la connexion suivante, et il '
            'faut l’accepter pour continuer.',
      ],
    ),
    LegalSection(
      '10. Droit applicable',
      paragraphs: [
        'Ces conditions suivent le droit de la République démocratique du '
            'Congo. En cas de désaccord, on essaie d’abord de se parler.',
      ],
    ),
  ],
);

const privacyDoc = LegalDoc(
  title: 'Confidentialité',
  subtitle:
      'Les données que Ding garde, pourquoi, combien de temps, et qui peut les '
      'voir. Rien de ce qui suit n’est une formule : chaque ligne correspond à '
      'quelque chose dans le code.',
  sections: [
    LegalSection(
      '1. Ce qui est enregistré',
      bullets: [
        'Ton compte : email, prénom, mot de passe haché (bcrypt — jamais en '
            'clair), faculté et promotion si tu les renseignes.',
        'Tes choix : les personnes que tu as désignées. Visibles par toi '
            'seul.',
        'Ta position : latitude, longitude, heure. Effacée au bout de '
            '24 heures.',
        'Tes alarmes : la date et avec qui. Conservées 30 jours.',
        'Tes signalements : motif et texte libre, conservés comme trace de la '
            'décision.',
        'Des journaux techniques : méthode, route, code de réponse, durée. '
            'Jamais le corps des requêtes, jamais les coordonnées.',
      ],
    ),
    LegalSection(
      '2. Ce que personne ne voit',
      bullets: [
        'Ta position : elle n’est renvoyée à aucun autre utilisateur, et '
            'aucune route de l’API ne la donne.',
        'Les personnes que tu as choisies : jamais.',
        'Qui t’a choisi : jamais, même quand l’alarme sonne. C’est l’alarme '
            'qui te prévient, pas une liste.',
        'Qui a signalé : le signalant n’apparaît pas dans l’outil de '
            'modération.',
      ],
    ),
    LegalSection(
      '3. Pourquoi',
      bullets: [
        'Faire sonner l’alarme : comparer deux positions et deux choix, sur '
            'le serveur.',
        'Sécuriser les comptes : compter les essais de mot de passe ratés.',
        'Modérer : lire un signalement et décider.',
        'Rien d’autre. Pas de profilage publicitaire, pas de revente.',
      ],
    ),
    LegalSection(
      '4. Combien de temps',
      bullets: [
        'Position : 24 heures, puis supprimée automatiquement.',
        'Alarme : 30 jours.',
        'Code de réinitialisation : 15 minutes.',
        'Jeton de session fermé : jusqu’à sa date d’expiration.',
        'Compte, choix et prénom : jusqu’à la suppression du compte.',
      ],
    ),
    LegalSection(
      '5. Qui y a accès',
      bullets: [
        'L’équipe du campus, pour la modération : elle voit le prénom, la '
            'faculté et le motif d’un profil signalé. Elle ne voit ni qui a '
            'signalé, ni les positions.',
        'L’hébergeur du serveur et de la base de données, qui traite ces '
            'données pour notre compte.',
        'Le service d’envoi d’emails, uniquement pour les codes de '
            'réinitialisation.',
        'Personne d’autre : pas de revente, pas de courtier en données.',
      ],
    ),
    LegalSection(
      '6. Tes droits',
      bullets: [
        'Voir et corriger tes informations : depuis ton profil.',
        'Disparaître de l’annuaire : un interrupteur dans ton profil.',
        'Effacer : la suppression du compte efface le profil, les choix, les '
            'alarmes et les positions. Les signalements déposés ou reçus '
            'partent avec le compte.',
        'T’opposer ou demander une explication : écris-nous, on répond.',
        'Réclamer : auprès de l’autorité de protection des données '
            'compétente.',
      ],
    ),
    LegalSection(
      '7. Sécurité',
      bullets: [
        'Le jeton de session est conservé dans le Keystore Android, pas dans '
            'un fichier lisible par une autre app.',
        'Tout le trafic passe en HTTPS.',
        'Les mots de passe ne sont jamais stockés en clair et n’apparaissent '
            'jamais dans les journaux.',
        'Les routes sont limitées en débit pour empêcher le bourrage de mots '
            'de passe et l’énumération des profils.',
      ],
    ),
    LegalSection(
      '8. Âge',
      paragraphs: [
        'Ding est réservé aux personnes majeures. Un compte manifestement '
            'tenu par une personne mineure est suspendu dès qu’il est '
            'signalé.',
      ],
    ),
  ],
);
