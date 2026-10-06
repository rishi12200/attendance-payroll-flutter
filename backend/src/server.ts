import { env } from './config/env';
import { auth, projectId } from './config/firebase';
import { createApp } from './app';
import { getUserProfile } from './services/profile';

const app = createApp({
  verifyIdToken: (token, checkRevoked) => auth.verifyIdToken(token, checkRevoked),
  getProfile: getUserProfile,
});

app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}  (Firebase project: ${projectId})`);
});
