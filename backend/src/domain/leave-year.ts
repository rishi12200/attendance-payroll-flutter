import { isValidDateString } from './dates';

export interface LeaveYear {
  year: number;
  startDate: string;
  endDate: string;
  label: string;
}

const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

export function leaveYearOf(dateString: string, startMonth: number): LeaveYear {
  if (!isValidDateString(dateString)) {
    throw new RangeError('Leave year requires a valid YYYY-MM-DD date.');
  }
  validateStartMonth(startMonth);
  const calendarYear = Number(dateString.slice(0, 4));
  const calendarMonth = Number(dateString.slice(5, 7));
  const year = calendarMonth >= startMonth ? calendarYear : calendarYear - 1;
  return leaveYearByYear(year, startMonth);
}

export function leaveYearByYear(year: number, startMonth: number): LeaveYear {
  validateStartMonth(startMonth);
  if (!Number.isInteger(year) || year < 1 || year > 9998) {
    throw new RangeError('Leave year must be a calendar year from 1 to 9998.');
  }
  const endYear = startMonth === 1 ? year : year + 1;
  const endMonth = startMonth === 1 ? 12 : startMonth - 1;
  const endDay = daysInMonth(endYear, endMonth);
  const startDate = `${String(year).padStart(4, '0')}-${pad(startMonth)}-01`;
  const endDate = `${String(endYear).padStart(4, '0')}-${pad(endMonth)}-${pad(endDay)}`;
  const label = startMonth === 1
    ? String(year)
    : `${monthNames[startMonth - 1]} ${year} - ${monthNames[endMonth - 1]} ${endYear}`;
  return { year, startDate, endDate, label };
}

function validateStartMonth(startMonth: number): void {
  if (!Number.isInteger(startMonth) || startMonth < 1 || startMonth > 12) {
    throw new RangeError('Leave-year start month must be an integer from 1 to 12.');
  }
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) {
    const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    return leap ? 29 : 28;
  }
  return [4, 6, 9, 11].includes(month) ? 30 : 31;
}

function pad(value: number): string {
  return String(value).padStart(2, '0');
}
