# Ding API

API REST Node.js + PostgreSQL. Le matching se fait côté serveur : aucune route ne révèle qui a choisi qui, ni les positions des autres.

## Routes

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/auth/signup` | Créer un compte (`first_name`, `email`, `password`, `accept_terms: true` — obligatoire) |
| POST | `/auth/login` | Se connecter (`email`, `password`) |
| POST | `/auth/forgot` | Demander un code de réinitialisation (`email`) |
| POST | `/auth/reset` | Échanger le code contre un mot de passe (`email`, `code`, `password`) |
| POST | `/auth/logout` | Révoquer le jeton courant (déconnexion côté serveur) |
| POST | `/auth/verify-email` | Confirmer l'adresse (`code` à 6 chiffres) |
| POST | `/auth/verify-email/resend` | Renvoyer un code (un par minute maximum) |
| POST | `/auth/accept-terms` | Accepter la version courante des CGU |
| GET | `/config` | Réglages publics : rayon d'alarme, intervalles, version des CGU |
| GET / PUT / DELETE | `/me` | Lire / modifier / supprimer mon compte |
| GET | `/profiles` | Annuaire paginé : `q`, `limit` (1–100), `offset` → `{items, total, next_offset}` |
| GET | `/crushes` | Mes choix uniquement |
| POST | `/crushes/:id` | Choisir quelqu'un (idempotent) |
| DELETE | `/crushes/:id` | Retirer un choix (idempotent) |
| POST | `/crushes/:id/toggle` | *(déprécié)* inverse l'état — conservé pour les anciennes versions de l'app |
| GET | `/blocks` | Personnes que j'ai bloquées |
| POST | `/blocks/:id` | Bloquer : retire de l'annuaire, efface les choix et les alarmes de la paire |
| DELETE | `/blocks/:id` | Débloquer |
| POST | `/reports/:id` | Signaler (`reason` : `harcelement`, `faux_profil`, `intimidation`, `autre`) |
| GET | `/admin/reports` | **Modérateur.** File des personnes signalées, groupée par personne (`?status=all` pour l'historique) |
| POST | `/admin/reports/:id/resolve` | **Modérateur.** Refermer : `{action: "dismiss" \| "ban", note?}` |
| POST | `/admin/users/:id/restore` | **Modérateur.** Lever une suspension |
| POST | `/location` | Envoyer ma position (`lat`, `lng`) — **403 si l'email n'est pas vérifié** |
| GET | `/alarms` | Mes alarmes |
| GET | `/health` | Vérification (pour l'hébergeur) |

## Modération

Les modérateurs sont désignés par la variable `ADMIN_EMAILS` (liste d'emails
séparés par des virgules). Aucun écran ne permet de s'attribuer le rôle : il
faut modifier la configuration, puis redémarrer l'API.

Ce que l'outil permet, et rien de plus :

- **Voir** les profils signalés, avec le nombre de signalements et le motif le
  plus récent. L'identité de la personne qui signale n'est jamais renvoyée,
  pas même à l'équipe (`reporter_id` n'apparaît dans aucune réponse).
- **Classer sans suite** : les signalements ouverts du profil passent en
  `dismissed`.
- **Suspendre** : les signalements passent en `banned`, le compte reçoit une
  date de suspension (`banned_at`), sa position et ses choix sont effacés, il
  disparaît de l'annuaire et ses jetons cessent d'être acceptés à la requête
  suivante. Une réactivation se fait à la main en base : c'est volontaire.

Les décisions restent en base (`resolved_by`, `resolution`, `resolved_at`)
comme trace de ce qui a été décidé, et par qui.

## Vérification d'email

À l'inscription, un code à 6 chiffres part par email (même mécanisme que la
réinitialisation : `mailer.js`, et les logs du serveur si `RESEND_API_KEY` est
absent). Il vit 24 heures, tolère 5 essais, et un renvoi est possible une fois
par minute.

Une adresse non vérifiée n'empêche pas d'utiliser l'app : annuaire, choix
secrets, profil. Elle empêche **l'envoi de position**, donc l'alarme. C'est le
compromis retenu : un compte jetable ne doit pas pouvoir faire sonner le
téléphone de quelqu'un, mais on ne veut pas non plus bloquer l'app entière
parce qu'un email a atterri dans les indésirables.

Les comptes créés avant l'arrivée de cette fonctionnalité sont marqués comme
vérifiés une seule fois au démarrage (marqueur `app_meta`), pour ne pas couper
l'alarme de personnes déjà inscrites.

## Conditions d'utilisation

`POST /auth/signup` refuse une inscription sans `accept_terms: true` et garde
la version acceptée (`terms_version`, `terms_accepted_at`). La version en
cours est publiée par `GET /config` : l'app peut ainsi savoir qu'un texte plus
récent existe. Le texte lui-même vit dans l'app
(`lib/features/legal/legal_texts.dart`), pas dans l'API.

## Déployer gratuitement

**1. Base de données (Neon)**
1. Crée un projet sur neon.tech.
2. Copie la chaîne de connexion (`postgresql://...`).
Les tables se créent toutes seules au premier démarrage.

**2. API (Render)**
1. Mets le dépôt sur GitHub, puis sur render.com : New > Web Service.
2. Choisis le dépôt, puis règle :
   - Root Directory : `api`
   - Build Command : `npm install`
   - Start Command : `npm start`
   - Instance type : Free
3. Dans Environment, ajoute :
   - `DATABASE_URL` : la chaîne Neon
   - `JWT_SECRET` : une longue valeur aléatoire (ex. `openssl rand -hex 32`)
   - `ALLOWED_EMAIL_DOMAIN` : optionnel (mode campus)
4. Déploie, puis teste `https://ton-api.onrender.com/health`.

**Limite de l'offre gratuite** : l'API se met en veille après un moment sans appel, et le premier appel suivant peut prendre environ une minute. Les conditions des offres gratuites changent : vérifie-les sur le site de l'hébergeur. Pour limiter la veille, un service de ping (ex. UptimeRobot) peut appeler `/health` toutes les 5 minutes.

## Limites de débit et verrouillage

- `/auth/*` : 30 requêtes / 15 min par IP.
- Verrouillage par compte : 10 échecs de connexion → 15 minutes de blocage.
  La limite par IP ne protège pas d'un bourrage ciblé depuis un réseau partagé.
- `/location` : 20 requêtes / min (chaque appel recalcule les alarmes).
- Autres routes authentifiées : 240 requêtes / min.

## Emails

`RESEND_API_KEY` absente → les emails (code de réinitialisation) sont écrits
dans les logs du serveur. C'est le mode utilisé en développement et dans la CI.

Avec une clé Resend (offre gratuite : 3 000 emails/mois) :

```
RESEND_API_KEY=re_...
MAIL_FROM=Ding <no-reply@ton-domaine.fr>
```

`MAIL_FROM` doit utiliser un domaine vérifié chez Resend, sinon Resend refuse
l'envoi. En attendant, `onboarding@resend.dev` fonctionne pour des tests vers
ta propre adresse.

## Suppression d'un compte

`DELETE /me` exige le mot de passe dans le corps. Tout part en cascade
(choix, positions, alarmes, codes de réinitialisation).

## Entretien

Au démarrage puis toutes les 6 h, l'API purge les positions de plus de 24 h
(elles ne servent plus à rien : seules celles de moins de 15 min comptent) et
les alarmes de plus de 30 jours.

## En local

```bash
cd api
npm install
DATABASE_URL=postgresql://user:pass@localhost:5432/ding DATABASE_SSL=false JWT_SECRET=secret npm start
```
