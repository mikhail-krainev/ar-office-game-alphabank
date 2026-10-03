import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type PlayerSummary } from "./api";
import type { DashboardActions } from "./Dashboard";
import { Dropdown } from "./Dropdown";
import { formatDateTime, formatDay, formatPlayTime } from "./format";
import { PLAY_STATES } from "./labels";
import { PlayerStats } from "./PlayerStats";

type SortKey = "created" | "activity" | "streak" | "office_days" | "tasks" | "coins" | "play";

const SORTS: { value: SortKey; label: string; key: (p: PlayerSummary) => number }[] = [
  { value: "created", label: "Сначала новые", key: (p) => p.created_at },
  { value: "activity", label: "По последней активности", key: (p) => p.last_activity },
  { value: "streak", label: "По серии дней", key: (p) => p.streak * 10000 + p.best_streak },
  { value: "office_days", label: "По дням в офисе", key: (p) => p.office_days },
  { value: "tasks", label: "По заданиям", key: (p) => p.tasks_total },
  { value: "coins", label: "По заработанным монетам", key: (p) => p.coins_earned },
  { value: "play", label: "По времени в игре сегодня", key: (p) => p.play_seconds_today },
];

const ALL_DEPARTMENTS = "__all__";
const ALL_OFFICES = "__all__";

/** Statistics: all players at a glance; a row opens the player's full activity audit. */
export function StatsPanel({ actions }: { actions: DashboardActions }) {
  const { session, departments, offices, report, officeName } = actions;
  const [players, setPlayers] = useState<PlayerSummary[] | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [office, setOffice] = useState(ALL_OFFICES);
  const [department, setDepartment] = useState(ALL_DEPARTMENTS);
  const [sort, setSort] = useState<SortKey>("created");

  const load = useCallback(async () => {
    try {
      setPlayers(await api.statsOverview(session));
    } catch (e) {
      report(e);
    }
  }, [session, report]);

  useEffect(() => {
    void load();
  }, [load]);

  const departmentName = useCallback(
    (id: string) => departments.find((d) => d.id === id)?.name ?? "—",
    [departments],
  );

  const visible = useMemo(() => {
    const text = query.trim().toLowerCase();
    const sortKey = SORTS.find((s) => s.value === sort)!.key;
    return (players ?? [])
      .filter((p) => office === ALL_OFFICES || p.office_id === office)
      .filter((p) => department === ALL_DEPARTMENTS || p.department_id === department)
      .filter((p) => !text || p.display_name.toLowerCase().includes(text) || p.username.includes(text))
      .sort((a, b) => sortKey(b) - sortKey(a));
  }, [players, query, office, department, sort]);

  if (selected) {
    return (
      <PlayerStats
        actions={actions}
        userId={selected}
        departmentName={departmentName}
        onBack={() => {
          setSelected(null);
          void load();
        }}
      />
    );
  }

  const ofOffice = (players ?? []).filter((p) => office === ALL_OFFICES || p.office_id === office);
  const inOffice = ofOffice.filter((p) => p.in_office).length;
  const presentToday = ofOffice.filter((p) => p.present_today).length;
  const limited = ofOffice.filter((p) => p.play_state === "resting" || p.play_state === "blocked").length;
  const onTrip = ofOffice.filter((p) => p.trip).length;

  return (
    <section className="card">
      <div className="section-head">
        <h2>Статистика игроков</h2>
        <button className="secondary" onClick={() => void load()}>
          Обновить
        </button>
      </div>
      {players && (
        <p className="muted summary-line">
          Игроков: <b>{ofOffice.length}</b> · сейчас в офисе: <b>{inOffice}</b> · были сегодня: <b>{presentToday}</b> · на
          отдыхе или закрыто: <b>{limited}</b> · в командировке: <b>{onTrip}</b>
        </p>
      )}
      <div className="filters">
        <input placeholder="Поиск по имени или логину" value={query} onChange={(e) => setQuery(e.target.value)} />
        <Dropdown
          value={office}
          placeholder="Офис"
          options={[{ value: ALL_OFFICES, label: "Все офисы" }, ...offices.map((o) => ({ value: o.id, label: o.name }))]}
          onChange={(value) => {
            setOffice(value);
            setDepartment(ALL_DEPARTMENTS);
          }}
        />
        <Dropdown
          value={department}
          placeholder="Департамент"
          options={[
            { value: ALL_DEPARTMENTS, label: "Все департаменты" },
            ...departments
              .filter((d) => office === ALL_OFFICES || d.office_id === office)
              .map((d) => ({ value: d.id, label: office === ALL_OFFICES ? `${d.name} · ${officeName(d.office_id)}` : d.name })),
          ]}
          onChange={setDepartment}
        />
        <Dropdown value={sort} placeholder="Сортировка" options={SORTS} onChange={(value) => setSort(value as SortKey)} />
      </div>
      {players === null ? (
        <p className="muted">Загрузка…</p>
      ) : visible.length === 0 ? (
        <p className="muted">Никого не найдено.</p>
      ) : (
        <div className="table-wrap">
          <table className="stats-table">
            <thead>
              <tr>
                <th>Игрок</th>
                <th>Офис и департамент</th>
                <th>Сейчас</th>
                <th className="num">Серия</th>
                <th className="num">Лучшая</th>
                <th className="num">Дней в офисе</th>
                <th className="num">Заданий</th>
                <th className="num">Заработано</th>
                <th className="num">Баланс</th>
                <th className="num">В игре сегодня</th>
                <th>Последняя активность</th>
              </tr>
            </thead>
            <tbody>
              {visible.map((p) => (
                <tr key={p.id} className={`clickable${p.banned ? " banned" : ""}`} onClick={() => setSelected(p.id)}>
                  <td>
                    <div className="player-name">{p.display_name}</div>
                    <code className="muted">{p.username}</code>
                  </td>
                  <td className="nowrap">
                    {officeName(p.office_id)}
                    <div className="muted">{departmentName(p.department_id)}</div>
                    {p.trip && <span className="badge soft">в командировке: {officeName(p.trip.office_id)}</span>}
                  </td>
                  <td>
                    <PresenceBadge player={p} /> <PlayBadge player={p} />
                  </td>
                  <td className="num">
                    <b>{p.streak}</b>
                  </td>
                  <td className="num">{p.best_streak}</td>
                  <td className="num">{p.office_days}</td>
                  <td className="num">{p.tasks_total}</td>
                  <td className="num">{p.coins_earned}</td>
                  <td className="num">{p.balance}</td>
                  <td className="num nowrap">{formatPlayTime(p.play_seconds_today)}</td>
                  <td className="nowrap">
                    {p.last_activity ? formatDateTime(p.last_activity) : p.last_login_day ? formatDay(p.last_login_day) : "не играл"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

/** Continuous-play limit state; nothing while the player plays within the limit. */
export function PlayBadge({ player }: { player: PlayerSummary }) {
  if (player.banned || player.play_state === "ok" || !player.play_state) {
    return null;
  }
  return <span className={player.play_state === "warning" ? "badge soft" : "badge missed"}>{PLAY_STATES[player.play_state]}</span>;
}

export function PresenceBadge({ player }: { player: PlayerSummary }) {
  if (player.banned) {
    return <span className="badge muted-badge">заблокирован</span>;
  }
  if (player.in_office) {
    return <span className="badge present">в офисе</span>;
  }
  if (player.present_today) {
    return <span className="badge soft">был сегодня</span>;
  }
  if (!player.first_day) {
    return <span className="badge muted-badge">не начинал</span>;
  }
  return <span className="badge muted-badge">не в офисе</span>;
}
