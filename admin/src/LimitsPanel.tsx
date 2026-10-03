import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api, type Limits } from "./api";
import type { DashboardActions } from "./Dashboard";
import { formatMinutes } from "./format";
import { OfficeSelect } from "./OfficeSelect";

// Server ranges (server/modules/limits.go).
const RANGES = {
  task_cooldown_minutes: [0, 240],
  play_limit_minutes: [5, 480],
  exit_grace_minutes: [1, 60],
  rest_minutes: [1, 240],
} as const;

type NumberField = keyof typeof RANGES;

/**
 * Working-time limits of one office: how often tasks count and how long one may play without a break.
 * A player follows the limits of the office they are in today (the trip office on a business trip).
 */
export function LimitsPanel({ actions }: { actions: DashboardActions }) {
  const { session, run, report } = actions;
  const [officeId, setOfficeId] = useState(actions.offices[0]?.id ?? "");
  const [saved, setSaved] = useState<Limits | null>(null);
  const [defaults, setDefaults] = useState<Limits | null>(null);
  const [form, setForm] = useState<Limits | null>(null);
  const [notice, setNotice] = useState("");

  useEffect(() => {
    if (!officeId && actions.offices.length) {
      setOfficeId(actions.offices[0].id);
    }
  }, [officeId, actions.offices]);

  const load = useCallback(async () => {
    if (!officeId) {
      return;
    }
    try {
      const result = await api.getLimits(session, officeId);
      setSaved(result.limits);
      setDefaults(result.defaults);
      setForm(result.limits);
    } catch (e) {
      report(e);
    }
  }, [session, report, officeId]);

  useEffect(() => {
    void load();
  }, [load]);

  const picker = (
    <div className="office-picker">
      <label>
        Офис
        <OfficeSelect
          actions={actions}
          value={officeId}
          onChange={(id) => {
            setNotice("");
            setForm(null);
            setOfficeId(id);
          }}
        />
      </label>
    </div>
  );

  if (!form || !saved || !defaults) {
    return (
      <section className="card">
        <h2>Ограничения</h2>
        {picker}
        <p className="muted">Загрузка…</p>
      </section>
    );
  }

  const changed = JSON.stringify(form) !== JSON.stringify(saved);
  const windowValid = form.task_window_start < form.task_window_end;

  function setNumber(field: NumberField, text: string) {
    setNotice("");
    setForm((current) => (current ? { ...current, [field]: text === "" ? 0 : Math.round(Number(text)) } : current));
  }

  function setClock(field: "task_window_start" | "task_window_end", text: string) {
    setNotice("");
    setForm((current) => (current ? { ...current, [field]: text } : current));
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!form) {
      return;
    }
    let next: Limits | null = null;
    const ok = await run(async () => {
      next = await api.setLimits(session, officeId, form);
    });
    if (ok && next) {
      setSaved(next);
      setForm(next);
      setNotice(`Сохранено для офиса «${actions.officeName(officeId)}». Новые значения действуют со следующего действия игроков.`);
    }
  }

  const numberInput = (field: NumberField) => (
    <input
      type="number"
      inputMode="numeric"
      min={RANGES[field][0]}
      max={RANGES[field][1]}
      step={1}
      value={form[field]}
      onChange={(e) => setNumber(field, e.target.value)}
      required
    />
  );

  return (
    <form onSubmit={submit}>
      {picker}
      <section className="card">
        <h2>Задания</h2>
        <p className="muted">
          Каждый рабочий день игрок получает свой случайный набор заданий: половину всех заданий в один день и оставшуюся
          половину на следующий рабочий день. Отметка на ресепшне есть всегда и в ограничения ниже не входит.
        </p>
        <div className="grid-form limits-form">
          <label>
            Пауза между заданиями, мин
            {numberInput("task_cooldown_minutes")}
            <span className="hint">0 — без паузы. Отсчёт от момента, когда засчитано предыдущее задание.</span>
          </label>
          <label>
            Задания засчитываются с
            <input type="time" value={form.task_window_start} onChange={(e) => setClock("task_window_start", e.target.value)} required />
            <span className="hint">По времени офиса.</span>
          </label>
          <label>
            до
            <input type="time" value={form.task_window_end} onChange={(e) => setClock("task_window_end", e.target.value)} required />
            {!windowValid && <span className="hint error">Конец должен быть позже начала.</span>}
          </label>
        </div>
      </section>

      <section className="card">
        <h2>Время в игре</h2>
        <p className="muted">
          Считается непрерывная игра: всё время, пока игра открыта на экране. Перерыв не короче отдыха обнуляет счёт.
        </p>
        <div className="grid-form limits-form">
          <label>
            Предупреждение после, мин
            {numberInput("play_limit_minutes")}
            <span className="hint">Сколько можно играть без перерыва.</span>
          </label>
          <label>
            Время, чтобы выйти, мин
            {numberInput("exit_grace_minutes")}
            <span className="hint">Не вышел за это время — игра закрыта до завтра.</span>
          </label>
          <label>
            Отдых, мин
            {numberInput("rest_minutes")}
            <span className="hint">Вышел вовремя — после отдыха можно играть снова.</span>
          </label>
        </div>
        <div className="limits-preview">
          <span className="muted">Игрок увидит:</span>
          <p>
            «Вы проводите в игре уже более {formatMinutes(form.play_limit_minutes, true)}! Отдохните и вернитесь в игру через{" "}
            {formatMinutes(form.rest_minutes)}, иначе доступ на сегодня будет ограничен!» — и таймер на{" "}
            {formatMinutes(form.exit_grace_minutes)}.
          </p>
        </div>
      </section>

      <div className="form-actions">
        <button type="submit" disabled={!changed || !windowValid}>
          Сохранить
        </button>
        <button type="button" className="secondary" disabled={!changed} onClick={() => setForm(saved)}>
          Отменить изменения
        </button>
        <button
          type="button"
          className="link"
          disabled={JSON.stringify(form) === JSON.stringify(defaults)}
          onClick={() => {
            setNotice("");
            setForm(defaults);
          }}
        >
          Значения по умолчанию
        </button>
        {notice && <span className="muted">{notice}</span>}
      </div>
    </form>
  );
}
