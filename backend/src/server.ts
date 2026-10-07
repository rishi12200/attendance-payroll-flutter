import { env } from './config/env';
import { auth, db, projectId } from './config/firebase';
import { createApp } from './app';
import { getUserProfile } from './services/profile';
import { EmployeeService } from './services/employee-service';
import { FirestoreEmployeeStore } from './services/firestore-employee-store';
import { BranchService } from './services/branch-service';
import { FirestoreBranchStore } from './services/firestore-branch-store';

const employeeStore = new FirestoreEmployeeStore(db);
const branchStore = new FirestoreBranchStore(db);
const app = createApp({
  verifyIdToken: (token, checkRevoked) => auth.verifyIdToken(token, checkRevoked),
  getProfile: getUserProfile,
  employees: new EmployeeService({
    auth,
    store: employeeStore,
    branches: branchStore,
  }),
  branches: new BranchService(branchStore, employeeStore),
});

app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}  (Firebase project: ${projectId})`);
});
