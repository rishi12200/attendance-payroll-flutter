import { env } from './config/env';
import { projectId } from './config/firebase';
import { createApp } from './app';

const app = createApp();

app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}  (Firebase project: ${projectId})`);
});
