import { useEffect, useState } from "react";
import { api, type Clock } from "./api";
import type { DashboardActions } from "./Dashboard";
import { plural } from "./format";

const HOUR = 3600;
const DAY = 24 * HOUR;
/** Office time when the tasks of the next workday are worth checking. */
const MORNING_HOUR = 9;

const officeClock = new Intl.DateTimeFormat("ru-RU", {
  weekday: "long",
  day: "2-digit",
  month: "long",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  timeZone: "UTC",
});

/** "2 дня 5 ч" for a shift in seconds; "нет" for 0. */
function formatShift(seconds: number): string {
  if (seconds <= 0) {
    return "нет";
  }
  const days = Math.floor(seconds / DAY);
  const hours = Math.floor((seconds % DAY) / HOUR);
  const minutes = Math.floor((seconds % HOUR) / 60);
  const parts = [];
  if (days) {
    parts.push(`${days} ${plural(days, "день", "дня", "дней")}`);
  }
  if (hours) {
    parts.push(`${hours} ч`);
  }
  if (minutes && !days) {
    parts.push(`${minutes} мин`);
  }
  return parts.join(" ") || "меньше минуты";
}

/** Seconds from `now` to MORNING_HOUR of the next workday, office time. */
function untilNextWorkdayMorning(now: number, offsetSeconds: number): number {
  const local = new Date((now + offsetSeconds) * 1000);
  const target = new Date(Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + 1, MORNING_HOUR));
  while (target.getUTCDay() === 0 || target.getUTCDay() === 6) {
    target.setUTCDate(target.getUTCDate() + 1);
  }
  return target.getTime() / 1000 - offsetSeconds - now;
}

/**
 * Test clock (TEST_CLOCK=true on the server): moves the game time of every player forward, so days,
 * streaks, fines and statistics can be checked in minutes. The office screen codes keep the real time.
 */
export function ClockPanel({ actions, clock, onChange }: { actions: DashboardActions; clock: Clock; onChange: (clock: Clock) => void }) {
  const { session, run } = actions;
  const [loadedAt, setLoadedAt] = useState(() => Date.now());
  const [tick, setTick] = useState(() => Date.now());

  useEffect(() => {
    setLoadedAt(Date.now());
  }, [clock]);

  useEffect(() => {
    const timer = window.setInterval(() => setTick(Date.now()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  const offsetSeconds = clock.utc_offset_minutes * 60;
  const now = clock.now + Math.floor((tick - loadedAt) / 1000);

  async function setShift(shift: number) {
    const next = Math.min(Math.max(Math.round(shift), 0), clock.max_shift_seconds);
    let updated: Clock | null = null;
    const ok = await run(async () => {
      updated = await api.setClock(session, next);
    });
    if (ok && updated) {
      onChange(updated);
    }
  }

  const forward = (seconds: number) => setShift(clock.shift_seconds + seconds);

  return (
    <section className="card">
      <h2>Время</h2>
      <p className="muted">
        Тестовые часы сдвигают игровое время всех игроков вперёд: новые дни, серии, штрафы за пропуски, наборы заданий
        и статистику можно проверить за несколько минут. Коды входа и выхода на экране офиса работают по настоящему
        времени. Включено, потому что на сервере стоит TEST_CLOCK=true.
      </p>
      <div className="clock-now">
        <span className="muted">Время в игре (офис, UTC{clock.utc_offset_minutes >= 0 ? "+" : "−"}{Math.abs(clock.utc_offset_minutes / 60)})</span>
        <strong>{officeClock.format((now + offsetSeconds) * 1000)}</strong>
        <span className="muted">Сдвиг от настоящего времени: {formatShift(clock.shift_seconds)}</span>
      </div>
      <div className="form-actions">
        <button type="button" onClick={() => forward(untilNextWorkdayMorning(now, offsetSeconds))}>
          Следующий рабочий день, {String(MORNING_HOUR).padStart(2, "0")}:00
        </button>
        <button type="button" className="secondary" onClick={() => forward(DAY)}>
          +1 день
        </button>
        <button type="button" className="secondary" onClick={() => forward(HOUR)}>
          +1 час
        </button>
        <button type="button" className="secondary" onClick={() => forward(15 * 60)}>
          +15 минут
        </button>
        <button type="button" className="link" disabled={clock.shift_seconds === 0} onClick={() => setShift(0)}>
          Вернуть настоящее время
        </button>
      </div>
      <p className="muted">
        Сдвиг применяется со следующего действия игроков; в игре обновите экран, чтобы увидеть новый день. Возврат
        времени назад может запутать игру: например, пауза между заданиями отсчитается от «будущего» момента.
      </p>
    </section>
  );
}
