# Ding API

API REST Node.js + PostgreSQL. Le matching se fait côté serveur : aucune route ne révèle qui a choisi qui, ni les positions des autres.

## Routes

| Méthode | Route | Rôle |
|---|---|---|
| POST | `/auth/signup` | Créer un compte (`first_name`, `email`, `password`) |
| POST | `/auth/login` | Se connecter (`email`, `password`) |
| GET / PUT | `/me` | Lire / modifier mon profil |
| GET | `/profiles` | Annuaire du campus (champs publics) |
| GET | `/crushes` | Mes choix uniquement |
| POST | `/crushes/:id/toggle` | Choisir / retirer quelqu'un |
| POST | `/location` | Envoyer ma position (`lat`, `lng`) |
| GET | `/alarms` | Mes alarmes |
| GET | `/health` | Vérification (pour l'hébergeur) |

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

## En local

```bash
cd api
npm install
DATABASE_URL=postgresql://user:pass@localhost:5432/ding DATABASE_SSL=false JWT_SECRET=secret npm start
```
