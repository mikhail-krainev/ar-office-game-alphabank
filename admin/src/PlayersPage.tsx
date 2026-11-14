import { useMemo, type ReactNode } from "react";
import type { PlayerSummary } from "./api";
import type { DashboardActions } from "./actions";
import { PRESENCE_LABELS, PlayBadge, PresenceBadge, presenceOf, type Presence } from "./badges";
import { Dropdown } from "./Dropdown";
import { FilterBar, matches, useFilters, type FilterDef } from "./FilterBar";
import { formatDateTime, formatDay, formatPlayTime } from "./format";
import { PLAY_STATES } from "./labels";
import { href, navigate } from "./router";
import { EmptyState, Loading, PageHeader } from "./ui";

type SortKey = "created" | "name" | "activity" | "streak" | "office_days" | "tasks" | "coins" | "balance" | "play";

const SORTS: { value: SortKey; label: string; compare: (a: PlayerSummary, b: PlayerSummary) => number }[] = [
  { value: "created", label: "сначала новые", compare: (a, b) => b.created_at - a.created_at },
  { value: "name", label: "по имени", compare: (a, b) => a.display_name.localeCompare(b.display_name, "ru") },
  { value: "activity", label: "по активности", compare: (a, b) => b.last_activity - a.last_activity },
  { value: "streak", label: "по серии дней", compare: (a, b) => b.streak - a.streak || b.best_streak - a.best_streak },
  { value: "office_days", label: "по дням в офисе", compare: (a, b) => b.office_days - a.office_days },
  { value: "tasks", label: "по заданиям", compare: (a, b) => b.tasks_total - a.tasks_total },
  { value: "coins", label: "по заработку", compare: (a, b) => b.coins_earned - a.coins_earned },
  { value: "balance", label: "по балансу", compare: (a, b) => b.balance - a.balance },
  { value: "play", label: "по времени в игре", compare: (a, b) => b.play_seconds_today - a.play_seconds_today },
];

type Placement = "trip" | "guest" | "home";
const PLACEMENT_LABELS: Record<Placement, string> = { trip: "в командировке", guest: "в другом офисе по Wi-Fi", home: "в своём офисе" };

const DEFAULT_FILTERS = { q: "", office: "", department: "", presence: "", placement: "", play: "", sort: "created" };

function placementOf(player: PlayerSummary): Placement {
  if (player.trip) {
    return "trip";
  }
  return player.guest_office_id ? "guest" : "home";
}

/**
 * Players of the panel with search, filters and sorting; a row opens the player's page. The
 * admin and the manager share the list; `base` is the address of the section ("players"/"staff").
 */
export function PlayersPage({
  actions,
  base,
  title,
  description,
  headerActions,
  onCreate,
}: {
  actions: DashboardActions;
  base: string;
  title: string;
  description?: ReactNode;
  headerActions?: ReactNode;
  /** Shown in the empty list when the panel may create players. */
  onCreate?: () => void;
}) {
  const { players, offices, departments, officeName, departmentName } = actions;
  const { values, set, update, reset, active } = useFilters(`players:${base}`, DEFAULT_FILTERS);

  const filters: FilterDef[] = [
    ...(offices.length > 1 ? [{ key: "office", label: "Офис", allLabel: "все", options: offices.map((o) => ({ value: o.id, label: o.name })) }] : []),
    {
      key: "department",
      label: "Департамент",
      allLabel: "все",
      options: departments
        .filter((d) => !values.office || d.office_id === values.office)
        .map((d) => ({ value: d.id, label: values.office || offices.length < 2 ? d.name : `${d.name} · ${officeName(d.office_id)}` })),
    },
    { key: "presence", label: "Статус", allLabel: "любой", options: Object.entries(PRESENCE_LABELS).map(([value, label]) => ({ value, label })) },
    { key: "placement", label: "Где сегодня", allLabel: "везде", options: Object.entries(PLACEMENT_LABELS).map(([value, label]) => ({ value, label })) },
    {
      key: "play",
      label: "Лимит игры",
      allLabel: "любой",
      options: [{ value: "ok", label: "в норме" }, ...Object.entries(PLAY_STATES).map(([value, label]) => ({ value, label }))],
    },
  ];

  const visible = useMemo(() => {
    const compare = SORTS.find((sort) => sort.value === values.sort)?.compare ?? SORTS[0].compare;
    return (players ?? [])
      .filter((p) => !values.office || p.office_id === values.office)
      .filter((p) => !values.department || p.department_id === values.department)
      .filter((p) => !values.presence || presenceOf(p) === (values.presence as Presence))
      .filter((p) => !values.placement || placementOf(p) === values.placement)
      .filter((p) => !values.play || (p.play_state || "ok") === values.play)
      .filter((p) => matches(values.q, p.display_name, p.username, officeName(p.office_id), departmentName(p.department_id), p.status))
      .sort(compare);
  }, [players, values, officeName, departmentName]);

  return (
    <>
      <PageHeader title={title} description={description} actions={headerActions} />
      <section className="card flush">
        <FilterBar
          query={values.q}
          onQuery={(text) => set("q", text)}
          placeholder="Имя, логин или статус"
          filters={filters}
          values={values}
          onChange={(key, value) =>
            // A department of another office would hide everyone.
            key === "office" ? update({ office: value, department: "" }) : set(key as keyof typeof DEFAULT_FILTERS, value)
          }
          onReset={reset}
          active={active}
          shown={visible.length}
          total={players?.length ?? 0}
          noun={["сотрудник", "сотрудника", "сотрудников"]}
          extra={
            <div className="filter-item">
              <Dropdown prefix="Сортировка" value={values.sort} placeholder="" options={SORTS} onChange={(value) => set("sort", value)} />
            </div>
          }
        />
        {players === null ? (
          <Loading />
        ) : players.length === 0 ? (
          <EmptyState icon="users" title="Пока нет сотрудников">
            {onCreate ? (
              <button type="button" onClick={onCreate}>
                Добавить первого сотрудника
              </button>
            ) : (
              "Здесь появятся сотрудники ваших департаментов."
            )}
          </EmptyState>
        ) : visible.length === 0 ? (
          <EmptyState title="Никого не найдено">
            <button type="button" className="link" onClick={reset}>
              Сбросить фильтры
            </button>
          </EmptyState>
        ) : (
          <PlayersTable players={visible} base={base} actions={actions} />
        )}
      </section>
    </>
  );
}

function PlayersTable({ players, base, actions }: { players: PlayerSummary[]; base: string; actions: DashboardActions }) {
  const { officeName, departmentName } = actions;
  return (
    <div className="table-wrap">
      <table className="data-table">
        <thead>
          <tr>
            <th>Сотрудник</th>
            <th>Офис и департамент</th>
            <th>Статус</th>
            <th className="num">Серия</th>
            <th className="num">Дней в офисе</th>
            <th className="num">Заданий</th>
            <th className="num">Баланс</th>
            <th className="num">В игре сегодня</th>
            <th>Последняя активность</th>
          </tr>
        </thead>
        <tbody>
          {players.map((p) => {
            const to = href([base, p.id]);
            return (
              <tr key={p.id} className={`clickable${p.banned ? " banned" : ""}`} onClick={() => navigate(to)}>
                <td>
                  <a className="row-link" href={to} onClick={(e) => e.stopPropagation()}>
                    <span className="avatar small" aria-hidden="true">
                      {p.display_name.charAt(0).toUpperCase() || "?"}
                    </span>
                    <span>
                      <span className="player-name">{p.display_name}</span>
                      <code className="muted">{p.username}</code>
                    </span>
                  </a>
                </td>
                <td>
                  {officeName(p.office_id)}
                  <div className="muted">{departmentName(p.department_id)}</div>
                  {p.trip && <span className="badge soft">командировка: {officeName(p.trip.office_id)}</span>}
                  {p.guest_office_id && <span className="badge soft">сейчас: {officeName(p.guest_office_id)}</span>}
                </td>
                <td>
                  <div className="badge-row">
                    <PresenceBadge player={p} />
                    <PlayBadge player={p} />
                  </div>
                </td>
                <td className="num">
                  <b>{p.streak}</b>
                  <span className="muted inline"> / {p.best_streak}</span>
                </td>
                <td className="num">{p.office_days}</td>
                <td className="num">{p.tasks_total}</td>
                <td className="num">{p.balance}</td>
                <td className="num">{formatPlayTime(p.play_seconds_today)}</td>
                <td className="nowrap">
                  {p.last_activity ? formatDateTime(p.last_activity) : p.last_login_day ? formatDay(p.last_login_day) : <span className="muted">не играл</span>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
