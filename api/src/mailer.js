/**
 * Envoi d'emails.
 *
 * Deux modes, choisis automatiquement :
 *
 * 1. RESEND_API_KEY défini  → envoi réel via Resend (offre gratuite :
 *    3 000 emails/mois). Brevo, Postmark, Mailgun marchent de la même façon
 *    (une requête HTTP POST), il suffit d'adapter l'URL.
 * 2. Aucune clé             → l'email est écrit dans les logs du serveur.
 *    Pratique en développement : le code de réinitialisation s'affiche dans
 *    le terminal, sans rien configurer.
 *
 * Aucun email ne doit jamais faire échouer une requête utilisateur : les
 * erreurs d'envoi sont journalisées, pas propagées.
 */

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const MAIL_FROM = process.env.MAIL_FROM || 'Ding <onboarding@resend.dev>';
const APP_NAME = 'Ding';

async function sendViaResend({ to, subject, text }) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${RESEND_API_KEY}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({ from: MAIL_FROM, to: [to], subject, text }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Resend ${res.status}: ${body.slice(0, 200)}`);
  }
}

export async function sendMail({ to, subject, text }) {
  try {
    if (RESEND_API_KEY) {
      await sendViaResend({ to, subject, text });
      console.log(`Email envoyé à ${to}`);
    } else {
      // Mode développement : lisible dans les logs de Render ou du terminal.
      console.log(
        `\n──────── EMAIL NON ENVOYÉ (RESEND_API_KEY absente) ────────\n` +
          `À      : ${to}\n` +
          `Objet  : ${subject}\n\n${text}\n` +
          `──────────────────────────────────────────────────────────\n`,
      );
    }
    return true;
  } catch (e) {
    console.error('Envoi d’email impossible', e.message);
    return false;
  }
}

export function verificationEmail(code) {
  return {
    subject: `${APP_NAME} — confirme ton adresse`,
    text:
      `Ton code de vérification ${APP_NAME} est : ${code}\n\n` +
      `Il expire dans 24 heures. Tant que tu ne l'as pas saisi, l'alarme ne ` +
      `peut pas sonner : c'est ce qui empêche quelqu'un de créer un compte ` +
      `avec une adresse qui n'est pas la sienne.\n` +
      `Si tu n'es pas à l'origine de cette inscription, ignore cet email.`,
  };
}

export function reportNoticeEmail({ name, reports, reasons }) {
  return {
    subject: `${APP_NAME} — nouveau signalement`,
    text:
      `Un profil vient d'être signalé : ${name || 'profil sans prénom'}\n` +
      `Signalements reçus : ${reports}\n` +
      `Motif(s) : ${reasons}\n\n` +
      `Ouvre l'écran « Signalements » dans l'app (onglet Profil) pour ` +
      `classer le signalement ou suspendre le compte.\n\n` +
      `L'identité de la personne qui signale ne t'est pas communiquée, et ` +
      `ne doit pas être cherchée.`,
  };
}

export function resetCodeEmail(code) {
  return {
    subject: `${APP_NAME} — code de réinitialisation`,
    text:
      `Ton code de réinitialisation ${APP_NAME} est : ${code}\n\n` +
      `Il expire dans 15 minutes et ne peut être utilisé qu'une fois.\n` +
      `Si tu n'es pas à l'origine de cette demande, ignore cet email : ` +
      `ton mot de passe reste inchangé.`,
  };
}
