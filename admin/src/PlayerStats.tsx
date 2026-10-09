import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { api, type ActivityEvent, type LedgerEntry, type OfficeVisit, type PlayerStats as Stats, type StatsDay } from "./api";
import type { DashboardActions } from "./Dashboard";
import { Dropdown } from "./Dropdown";
import { formatDate, formatDateTime, formatDay, formatMinutes, formatPlayTime, formatTime, plural, weekdayOf } from "./format";
import {
  ACTIVITY_LABELS,
  LEDGER_LABELS,
  PHOTO_STATES,
  REWARD_STATES,
  ROOM_LABELS,
  SUSPICIOUS_ACTIONS,
  VISIT_ENDS,
  label,
  suspiciousLabel,
} from "./labels";
import { PlayBadge, PresenceBadge } from "./StatsPanel";
import { tripLabel } from "./TripForm";

type Tab = "days" | "journal" | "coins" | "fraud";

/** One player's audit: totals, attendance calendar, day-by-day history, journal, coins, anti-fraud. */
export function PlayerStats({
  actions,
  userId,
  departmentName,
  onBack,
}: {
  actions: DashboardActions;
  userId: string;
  departmentName: (id: string) => string;
  onBack: () => void;
}) {
  const { session, report } = actions;
  const [stats, setStats] = useState<Stats | null>(null);
  const [tab, setTab] = useState<Tab>("days");

  const load = useCallback(async () => {
    try {
      setStats(await api.playerStats(session, userId));
    } catch (e) {
      report(e);
    }
  }, [session, userId, report]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!stats) {
    return (
      <section className="card">
        <button className="link" onClick={onBack}>
          ← Все игроки
        </button>
        <p className="muted">Загрузка…</p>
      </section>
    );
  }

  const { player, names } = stats;
  const name = (id: string) => names[id] ?? id;
  const flaggedCount = stats.suspicious.length;

  return (
    <>
      <section className="card">
        <div className="section-head">
          <button className="link" onClick={onBack}>
            ← Все игроки
          </button>
          <button className="secondary" onClick={() => void load()}>
            Обновить
          </button>
        </div>
        <div className="player-head">
          <div>
            <h2 className="player-title">
              {player.display_name} <PresenceBadge player={player} /> <PlayBadge player={player} />
            </h2>
            <p className="muted">
              <code>{player.username}</code> · {actions.officeName(player.office_id)} · {departmentName(player.department_id)} · аккаунт
              создан {formatDateTime(player.created_at)}
            </p>
            {player.trip && (
              <p>
                <span className="badge soft">в командировке: {tripLabel(actions, player.trip)}</span>
              </p>
            )}
            <p className="muted">
              {player.first_day ? <>Играет с {formatDay(player.first_day)}</> : "Ещё не входил в игру"}
              {player.last_activity ? <> · последняя активность {formatDateTime(player.last_activity)}</> : null}
              {player.status ? <> · статус «{player.status}»</> : null}
            </p>
          </div>
        </div>
        <div className="tiles">
          <Tile value={player.streak} label={`${plural(player.streak, "день", "дня", "дней")} подряд`} accent />
          <Tile value={player.best_streak} label="лучшая серия" />
          <Tile value={player.office_days} label="дней в офисе" />
          <Tile value={player.tasks_total} label="заданий выполнено" />
          <Tile value={player.skipped_total} label="заданий пропущено" />
          <Tile value={player.colleagues} label="коллег встречено" />
          <Tile value={player.coins_earned} label="монет заработано" />
          <Tile value={player.balance} label="монет на балансе" />
          <Tile value={formatPlayTime(player.play_seconds_today)} label="в игре сегодня" />
        </div>
      </section>

      <section className="card">
        <h2>Посещаемость</h2>
        <AttendanceCalendar stats={stats} />
      </section>

      <section className="card">
        <div className="tabs" role="tablist">
          <TabButton tab="days" current={tab} onSelect={setTab}>
            По дням
          </TabButton>
          <TabButton tab="journal" current={tab} onSelect={setTab}>
            Журнал действий
          </TabButton>
          <TabButton tab="coins" current={tab} onSelect={setTab}>
            Монеты
          </TabButton>
          <TabButton tab="fraud" current={tab} onSelect={setTab}>
            Антифрод{flaggedCount > 0 && <span className="count">{flaggedCount}</span>}
          </TabButton>
        </div>
        {tab === "days" && <DaysTable days={stats.days} today={player.today} name={name} />}
        {tab === "journal" && <Journal stats={stats} name={name} />}
        {tab === "coins" && <CoinsTable ledger={stats.ledger} name={name} />}
        {tab === "fraud" && <FraudTab stats={stats} name={name} />}
      </section>
    </>
  );
}

function Tile({ value, label, accent = false }: { value: number | string; label: string; accent?: boolean }) {
  return (
    <div className={accent ? "tile accent" : "tile"}>
      <div className="tile-value">{value}</div>
      <div className="tile-label">{label}</div>
    </div>
  );
}

function TabButton({ tab, current, onSelect, children }: { tab: Tab; current: Tab; onSelect: (tab: Tab) => void; children: ReactNode }) {
  return (
    <button role="tab" aria-selected={tab === current} className={tab === current ? "tab active" : "tab"} onClick={() => onSelect(tab)}>
      {children}
    </button>
  );
}

const CALENDAR_WEEKS = 26;
const WEEKDAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];

/** Weeks as columns, Monday on top: office days, misses, excused days and weekends. */
function AttendanceCalendar({ stats }: { stats: Stats }) {
  const { player } = stats;
  const byDay = useMemo(() => new Map(stats.days.map((d) => [d.day, d])), [stats.days]);
  const excused = useMemo(() => new Set(stats.excused_days), [stats.excused_days]);
  const monday = player.today - ((player.today + 3) % 7);
  const start = monday - (CALENDAR_WEEKS - 1) * 7;
  const weeks: number[][] = [];
  for (let week = 0; week < CALENDAR_WEEKS; week++) {
    weeks.push(Array.from({ length: 7 }, (_, i) => start + week * 7 + i));
  }

  function cell(day: number) {
    const record = byDay.get(day);
    const weekend = (day + 3) % 7 >= 5;
    let kind = "none";
    let text = "";
    if (day > player.today) {
      kind = "future";
    } else if (!player.first_day || day < player.first_day) {
      kind = "none";
      text = "до начала игры";
    } else if (record?.present) {
      kind = "present";
      text = `в офисе, заданий: ${record.tasks.length}, монет: ${record.earned}`;
    } else if (excused.has(day)) {
      kind = "excused";
      text = "уважительная причина";
    } else if (weekend) {
      kind = "weekend";
      text = "выходной";
    } else if (day === player.today) {
      kind = "today";
      text = "сегодня, ещё не отметился";
    } else {
      kind = "missed";
      text = "пропуск";
    }
    return <span key={day} className={`cal-cell ${kind}`} title={`${formatDay(day)} (${weekdayOf(day)}): ${text || "—"}`} />;
  }

  return (
    <div className="calendar">
      <div className="cal-grid">
        <div className="cal-weekdays">
          {WEEKDAYS.map((w) => (
            <span key={w}>{w}</span>
          ))}
        </div>
        {weeks.map((week) => (
          <div key={week[0]} className="cal-week">
            {week.map(cell)}
          </div>
        ))}
      </div>
      <div className="cal-legend">
        <span>
          <i className="cal-cell present" /> в офисе
        </span>
        <span>
          <i className="cal-cell missed" /> пропуск
        </span>
        <span>
          <i className="cal-cell excused" /> уважительная причина
        </span>
        <span>
          <i className="cal-cell weekend" /> выходной
        </span>
      </div>
    </div>
  );
}

function AttendanceBadge({ day, today }: { day: StatsDay; today: number }) {
  if (day.present) {
    return <span className="badge present">в офисе</span>;
  }
  if (day.excused) {
    return <span className="badge soft">уважительная</span>;
  }
  if (!day.workday) {
    return <span className="badge muted-badge">выходной</span>;
  }
  if (day.day === today) {
    return <span className="badge muted-badge">ещё нет</span>;
  }
  return <span className="badge missed">пропуск</span>;
}

function DaysTable({ days, today, name }: { days: StatsDay[]; today: number; name: (id: string) => string }) {
  if (days.length === 0) {
    return <p className="muted">Игрок ещё не начинал играть.</p>;
  }
  return (
    <div className="table-wrap">
      <table className="stats-table days-table">
        <thead>
          <tr>
            <th>Дата</th>
            <th>Посещение</th>
            <th>Приход</th>
            <th>Уход</th>
            <th>Входы и выходы</th>
            <th>Выполненные задания</th>
            <th>Другое</th>
            <th className="num">В игре</th>
            <th className="num">Монеты</th>
          </tr>
        </thead>
        <tbody>
          {days.map((day) => (
            <tr key={day.day}>
              <td className="nowrap">
                <b>{formatDay(day.day)}</b>
                <div className="muted">{weekdayOf(day.day)}</div>
              </td>
              <td>
                <AttendanceBadge day={day} today={today} />
              </td>
              <td className="nowrap">{formatTime(day.checkin_at)}</td>
              <td className="nowrap">{formatTime(day.left_at)}</td>
              <td>
                <VisitList visits={day.visits ?? []} />
              </td>
              <td>
                {day.tasks.length === 0 ? (
                  <span className="muted">—</span>
                ) : (
                  <ul className="plain-list">
                    {day.tasks.map((task, i) => (
                      <li key={`${task.id}-${i}`}>
                        <span className="muted time">{formatTime(task.t)}</span> {task.title}{" "}
                        <span className="plus">+{task.reward}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </td>
              <td>
                <ul className="plain-list muted">
                  {day.pending.map((task) => (
                    <li key={`p-${task.id}`}>ждёт подтверждения: {task.name}</li>
                  ))}
                  {day.skipped.map((task) => (
                    <li key={`s-${task.id}`}>пропущено: {task.name}</li>
                  ))}
                  {day.met.length > 0 && <li>коллеги: {day.met.map(name).join(", ")}</li>}
                  {day.purchases.length > 0 && <li>покупки: {day.purchases.length}</li>}
                </ul>
              </td>
              <td className="num nowrap">{formatPlayTime(day.play_seconds)}</td>
              <td className="num">{day.earned > 0 ? <span className="plus">+{day.earned}</span> : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Stays in the office Wi-Fi: "09:02–12:30 · отключился от Wi-Fi", the open one "с 13:10 · в офисе". */
function VisitList({ visits }: { visits: OfficeVisit[] }) {
  if (visits.length === 0) {
    return <span className="muted">—</span>;
  }
  return (
    <ul className="plain-list">
      {visits.map((visit) => (
        <li key={visit.in} className="nowrap">
          {visit.out ? (
            <>
              {formatTime(visit.in)}–{formatTime(visit.out)} <span className="muted">· {label(VISIT_ENDS, visit.how ?? "")}</span>
            </>
          ) : (
            <>
              с {formatTime(visit.in)} <span className="muted">· в офисе</span>
            </>
          )}
        </li>
      ))}
    </ul>
  );
}

type JournalFilter = "all" | "presence" | "tasks" | "coins";

interface JournalRow {
  t: number;
  kind: JournalFilter;
  title: string;
  detail: string;
  amount?: number;
}

const PRESENCE_KINDS = new Set(["login", "check_in", "check_out", "office_out", "office_back", "room", "play_warning", "play_rest", "play_blocked"]);
const TASK_REASONS = new Set(["task_reward", "photo_partner_bonus", "facts_partner_bonus"]);

function activityRow(event: ActivityEvent, name: (id: string) => string): JournalRow {
  const params = event.params ?? {};
  const text = (key: string) => (typeof params[key] === "string" ? (params[key] as string) : "");
  let detail = "";
  switch (event.kind) {
    case "check_in":
      detail = text("office") ? `офис «${name(text("office"))}»` : "";
      break;
    case "check_out":
      detail = text("how") === "home" ? "кнопка «Поехать домой»" : "";
      break;
    case "office_out":
      detail = `${label(VISIT_ENDS, text("how"))} · последний раз в сети в ${formatTime(Number(params.at ?? 0))}`;
      break;
    case "room":
      detail = label(ROOM_LABELS, text("room"));
      break;
    case "task_taken":
      detail = `${name(text("task"))} · ${label(ROOM_LABELS, text("room"))}`;
      break;
    case "task_done":
      detail = `${name(text("task"))} · +${String(params.reward ?? 0)}`;
      break;
    case "task_pending":
      detail = `${name(text("task"))} · с ${name(text("partner"))}`;
      break;
    case "task_skipped":
      detail = name(text("task"));
      break;
    case "met": {
      const colleagues = Array.isArray(params.colleagues) ? (params.colleagues as string[]) : [];
      detail = `${name(text("task"))}: ${colleagues.map(name).join(", ")}`;
      break;
    }
    case "photo_answer":
      detail = `${name(text("from"))} · ${params.confirm ? "подтвердил" : "отклонил"}`;
      break;
    case "facts_sent":
      detail = `${name(text("task"))} · ${name(text("partner"))}`;
      break;
    case "facts_answer":
      detail = `${name(text("from"))} · угадал ${String(params.correct ?? 0)} из 5`;
      break;
    case "play_warning":
      detail = `играл без перерыва ${formatMinutes(Number(params.minutes ?? 0))}`;
      break;
    case "play_rest":
      detail = `отдых ${formatMinutes(Number(params.minutes ?? 0))}`;
      break;
    case "play_blocked":
      detail = "не вышел из игры после предупреждения";
      break;
  }
  return { t: event.t, kind: PRESENCE_KINDS.has(event.kind) ? "presence" : "tasks", title: label(ACTIVITY_LABELS, event.kind), detail };
}

function ledgerDetail(entry: LedgerEntry, name: (id: string) => string): string {
  if (entry.reason === "absence_fine" && entry.ref.startsWith("day:")) {
    return `за ${formatDay(Number(entry.ref.slice(4)))}`;
  }
  if (entry.reason === "welcome_bonus" || entry.reason === "dev_grant") {
    return "";
  }
  return name(entry.ref);
}

const JOURNAL_FILTERS: { value: JournalFilter; label: string }[] = [
  { value: "all", label: "Все события" },
  { value: "presence", label: "Входы, посещение и время в игре" },
  { value: "tasks", label: "Задания и коллеги" },
  { value: "coins", label: "Покупки и штрафы" },
];

/** Everything the player did, newest first: the activity journal merged with the wallet ledger. */
function Journal({ stats, name }: { stats: Stats; name: (id: string) => string }) {
  const [filter, setFilter] = useState<JournalFilter>("all");
  const rows = useMemo(() => {
    const all: JournalRow[] = [
      ...stats.activity.filter((e) => e.kind !== "task_done").map((e) => activityRow(e, name)),
      // Task rewards come from the ledger, which also covers the time before the activity journal.
      ...stats.ledger.map((entry) => ({
        t: entry.t,
        kind: TASK_REASONS.has(entry.reason) ? ("tasks" as const) : ("coins" as const),
        title: label(LEDGER_LABELS, entry.reason),
        detail: ledgerDetail(entry, name),
        amount: entry.change,
      })),
    ];
    return all.filter((row) => filter === "all" || row.kind === filter).sort((a, b) => b.t - a.t);
  }, [stats, name, filter]);

  return (
    <>
      <div className="filters narrow">
        <Dropdown value={filter} placeholder="Фильтр" options={JOURNAL_FILTERS} onChange={(value) => setFilter(value as JournalFilter)} />
        <span className="muted">
          {rows.length} {plural(rows.length, "событие", "события", "событий")}
        </span>
      </div>
      {rows.length === 0 ? (
        <p className="muted">Событий нет. Журнал действий ведётся с этой версии сервера; монеты — с первого входа.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Дата и время</th>
                <th>Событие</th>
                <th>Подробности</th>
                <th className="num">Монеты</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row, i) => (
                <tr key={`${row.t}-${i}`}>
                  <td className="nowrap">{formatDateTime(row.t)}</td>
                  <td className="nowrap">{row.title}</td>
                  <td>{row.detail || <span className="muted">—</span>}</td>
                  <td className="num">{row.amount === undefined ? "" : <Amount value={row.amount} />}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function Amount({ value }: { value: number }) {
  return <span className={value >= 0 ? "plus" : "minus"}>{value >= 0 ? `+${value}` : value}</span>;
}

function CoinsTable({ ledger, name }: { ledger: LedgerEntry[]; name: (id: string) => string }) {
  const income = ledger.filter((e) => e.change > 0).reduce((sum, e) => sum + e.change, 0);
  const spent = ledger.filter((e) => e.change < 0).reduce((sum, e) => sum - e.change, 0);
  const byReason = new Map<string, number>();
  for (const entry of ledger) {
    byReason.set(entry.reason, (byReason.get(entry.reason) ?? 0) + entry.change);
  }
  return (
    <>
      <div className="tiles small">
        <div className="tile">
          <div className="tile-value plus">+{income}</div>
          <div className="tile-label">начислено</div>
        </div>
        <div className="tile">
          <div className="tile-value minus">−{spent}</div>
          <div className="tile-label">списано</div>
        </div>
        {[...byReason].map(([reason, sum]) => (
          <div className="tile" key={reason}>
            <div className="tile-value">
              <Amount value={sum} />
            </div>
            <div className="tile-label">{label(LEDGER_LABELS, reason)}</div>
          </div>
        ))}
      </div>
      {ledger.length === 0 ? (
        <p className="muted">Операций с монетами нет.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Дата и время</th>
                <th>Операция</th>
                <th>Основание</th>
                <th className="num">Сумма</th>
              </tr>
            </thead>
            <tbody>
              {ledger.map((entry, i) => (
                <tr key={`${entry.t}-${i}`}>
                  <td className="nowrap">{formatDateTime(entry.t)}</td>
                  <td>{label(LEDGER_LABELS, entry.reason)}</td>
                  <td>{ledgerDetail(entry, name) || <span className="muted">—</span>}</td>
                  <td className="num">
                    <Amount value={entry.change} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function FraudTab({ stats, name }: { stats: Stats; name: (id: string) => string }) {
  return (
    <>
      <h3>Подозрительные действия</h3>
      {stats.suspicious.length === 0 ? (
        <p className="muted">Не найдено.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Дата и время</th>
                <th>Действие</th>
                <th>Причина</th>
              </tr>
            </thead>
            <tbody>
              {stats.suspicious.map((entry, i) => (
                <tr key={`${entry.t}-${i}`}>
                  <td className="nowrap">{formatDateTime(entry.t)}</td>
                  <td>{SUSPICIOUS_ACTIONS[entry.task] ?? name(entry.task)}</td>
                  <td>{suspiciousLabel(entry.reason)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h3>Фото с коллегами</h3>
      {stats.photo_requests.length === 0 ? (
        <p className="muted">Запросов не было.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Дата и время</th>
                <th>Задание</th>
                <th>Коллега</th>
                <th>Статус</th>
                <th className="num">Награда</th>
              </tr>
            </thead>
            <tbody>
              {[...stats.photo_requests].reverse().map((photo) => (
                <tr key={photo.id}>
                  <td className="nowrap">{formatDateTime(photo.t)}</td>
                  <td>{name(photo.task)}</td>
                  <td>{name(photo.partner)}</td>
                  <td>{label(PHOTO_STATES, photo.state)}</td>
                  <td className="num">{photo.reward}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <h3>Заявки на дорогие награды</h3>
      {stats.reward_requests.length === 0 ? (
        <p className="muted">Заявок нет.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Дата</th>
                <th>Награда</th>
                <th>Статус</th>
                <th className="num">Цена</th>
              </tr>
            </thead>
            <tbody>
              {stats.reward_requests.map((request, i) => (
                <tr key={`${request.t}-${i}`}>
                  <td className="nowrap">{formatDate(request.t)}</td>
                  <td>{name(request.item_id)}</td>
                  <td>{label(REWARD_STATES, request.status)}</td>
                  <td className="num">{request.price}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
