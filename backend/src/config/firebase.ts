import fs from 'fs';
import { initializeApp, getApps, cert, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { env } from './env';

function init() {
  if (getApps().length) return getApps()[0];

  if (env.credentialsPath) {
    if (!fs.existsSync(env.credentialsPath)) {
      console.error(`Service account key not found at: ${env.credentialsPath}`);
      console.error('Place the JSON file there, or fix GOOGLE_APPLICATION_CREDENTIALS in .env');
      process.exit(1);
    }
    const key = JSON.parse(fs.readFileSync(env.credentialsPath, 'utf8'));
    return initializeApp({
      credential: cert(key),
      projectId: key.project_id,
    });
  }

  // On Cloud Run there is no key file; Application Default Credentials are used.
  return initializeApp({ credential: applicationDefault() });
}

const app = init();

export const auth = getAuth(app);
export const db = getFirestore(app);
db.settings({ ignoreUndefinedProperties: true });

export const projectId = app.options.projectId;
