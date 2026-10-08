import { env } from './config/env';
import { auth, db, projectId } from './config/firebase';
import { createApp } from './app';
import { getUserProfile } from './services/profile';
import { EmployeeService } from './services/employee-service';
import { FirestoreEmployeeStore } from './services/firestore-employee-store';
import { BranchService } from './services/branch-service';
import { FirestoreBranchStore } from './services/firestore-branch-store';
import { AttendanceService } from './services/attendance-service';
import { FirestoreAttendanceStore } from './services/firestore-attendance-store';
import { FirestoreAttendanceViewsStore } from './services/firestore-attendance-views-store';
import { AttendanceViewsService } from './services/attendance-views-service';
import { SettingsService } from './services/settings-service';
import { HolidayService } from './services/holiday-service';
import { LeaveService } from './services/leave-service';
import { FirestoreLeaveStore } from './services/firestore-leave-store';

const employeeStore = new FirestoreEmployeeStore(db);
const branchStore = new FirestoreBranchStore(db);
const attendanceStore = new FirestoreAttendanceStore(db);
const attendanceViewsStore = new FirestoreAttendanceViewsStore(db);
const leaveStore = new FirestoreLeaveStore(db);
const app = createApp({
  verifyIdToken: (token, checkRevoked) => auth.verifyIdToken(token, checkRevoked),
  getProfile: getUserProfile,
  employees: new EmployeeService({
    auth,
    store: employeeStore,
    branches: branchStore,
  }),
  branches: new BranchService(branchStore, employeeStore),
  attendance: new AttendanceService({
    store: attendanceStore,
    employees: employeeStore,
    branches: branchStore,
  }),
  attendanceViews: new AttendanceViewsService({
    store: attendanceViewsStore,
    employees: employeeStore,
    branches: branchStore,
  }),
  settings: new SettingsService(attendanceViewsStore),
  holidays: new HolidayService(attendanceViewsStore),
  leaves: new LeaveService(leaveStore),
});

app.listen(env.PORT, () => {
  console.log(`API running on http://localhost:${env.PORT}  (Firebase project: ${projectId})`);
});
