// Dates for the admin panel. Unix times are shown in the browser's time zone; day numbers are
// office calendar days (days since 1970-01-01 in the office time zone), so they need no zone.

const SECONDS_PER_DAY = 86400;

const dateTime = new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const date = new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric" });
const time = new Intl.DateTimeFormat("ru-RU", { hour: "2-digit", minute: "2-digit" });
const dayDate = new Intl.DateTimeFormat("ru-RU", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" });
const dayWeekday = new Intl.DateTimeFormat("ru-RU", { weekday: "short", timeZone: "UTC" });

/** "25.09.2026, 14:05"; "—" for 0. */
export function formatDateTime(unix: number): string {
  return unix ? dateTime.format(unix * 1000) : "—";
}

export function formatDate(unix: number): string {
  return unix ? date.format(unix * 1000) : "—";
}

/** "14:05"; "—" for 0 or missing. */
export function formatTime(unix: number | undefined): string {
  return unix ? time.format(unix * 1000) : "—";
}

/** Office day number as "25.09.2026". */
export function formatDay(day: number): string {
  return day ? dayDate.format(day * SECONDS_PER_DAY * 1000) : "—";
}

export function weekdayOf(day: number): string {
  return dayWeekday.format(day * SECONDS_PER_DAY * 1000);
}

/** 90 -> "1 ч 30 мин", 60 -> "1 час", 5 -> "5 минут". `genitive` is for "более 1 часа". */
export function formatMinutes(minutes: number, genitive = false): string {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (hours === 0) {
    return `${rest} ${genitive ? plural(rest, "минуты", "минут", "минут") : plural(rest, "минуту", "минуты", "минут")}`;
  }
  if (rest === 0) {
    return `${hours} ${genitive ? plural(hours, "часа", "часов", "часов") : plural(hours, "час", "часа", "часов")}`;
  }
  return `${hours} ч ${rest} мин`;
}

/** Play time in seconds as "1 ч 05 мин" / "12 мин"; "—" for 0. */
export function formatPlayTime(seconds: number): string {
  if (!seconds) {
    return "—";
  }
  const minutes = Math.round(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)} ч ${String(minutes % 60).padStart(2, "0")} мин` : `${minutes} мин`;
}

/** "3 дня" style plural. */
export function plural(n: number, one: string, few: string, many: string): string {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) {
    return one;
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return few;
  }
  return many;
}
