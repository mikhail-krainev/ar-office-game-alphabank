import type { ReactNode } from "react";
import type { PlayerSummary } from "./api";
import type { DashboardActions } from "./actions";
import { PresenceBadge } from "./badges";
import { Icon, type IconName } from "./Icon";
import { href } from "./router";
import { EmptyState, Loading, PageHeader, StatCard } from "./ui";

export interface Attention {
  id: string;
  icon: IconName;
  text: ReactNode;
  href: string;
}

interface GroupRow {
  id: string;
  name: string;
  sub?: string;
  href: string;
  players: PlayerSummary[];
}

const LEADERS = 5;

function percent(part: number, total: number): string {
  return total ? `${Math.round((part / total) * 100)}%` : "—";
}

/**
 * Home page of a panel: today's numbers (each opens the filtered list), attendance by office or
 * department, what needs attention and the longest streaks.
 */
export function OverviewPage({
  actions,
  title,
  description,
  base,
  groupBy,
  attention,
  headerActions,
}: {
  actions: DashboardActions;
  title: string;
  description?: ReactNode;
  /** Address of the players list: "players" or "staff". */
  base: string;
  groupBy: "office" | "department";
  attention: Attention[];
  headerActions?: ReactNode;
}) {
  const { players, offices, departments, officeName } = actions;
  if (players === null) {
    return (
      <>
        <PageHeader title={title} description={description} />
        <Loading />
      </>
    );
  }

  const active = players.filter((p) => !p.banned);
  const count = (test: (p: PlayerSummary) => boolean) => active.filter(test).length;
  const list = (query: Record<string, string> = {}) => href([base], query);

  const groups: GroupRow[] =
    groupBy === "office"
      ? offices.map((office) => ({
          id: office.id,
          name: office.name,
          sub: office.city,
          href: href(["offices", office.id]),
          players: active.filter((p) => p.office_id === office.id),
        }))
      : departments.map((department) => ({
          id: department.id,
          name: department.name,
          sub: offices.length > 1 ? officeName(department.office_id) : undefined,
          href: list({ office: department.office_id, department: department.id }),
          players: active.filter((p) => p.department_id === department.id),
        }));

  const blocked = count((p) => p.play_state === "blocked");
  const never = count((p) => !p.first_day);
  const attentionItems: Attention[] = [
    ...attention,
    ...(blocked ? [{ id: "blocked", icon: "ban" as const, text: <>Игра закрыта до завтра: {blocked}</>, href: list({ play: "blocked" }) }] : []),
    ...(never ? [{ id: "never", icon: "user" as const, text: <>Ещё не начинали играть: {never}</>, href: list({ presence: "never" }) }] : []),
  ];

  const leaders = [...active].filter((p) => p.streak > 0).sort((a, b) => b.streak - a.streak || b.office_days - a.office_days).slice(0, LEADERS);

  return (
    <>
      <PageHeader title={title} description={description} actions={headerActions} />
      <div className="stat-grid">
        <StatCard label="Сотрудников" value={active.length} hint={players.length > active.length ? `ещё ${players.length - active.length} заблокировано` : undefined} href={list()} />
        <StatCard label="Сейчас в офисе" value={count((p) => p.on_site)} tone="good" href={list({ presence: "on_site" })} />
        <StatCard label="Были сегодня" value={count((p) => p.present_today)} hint={`${percent(count((p) => p.present_today), active.length)} сотрудников`} />
        <StatCard label="В командировке" value={count((p) => !!p.trip)} href={list({ placement: "trip" })} />
        <StatCard label="На отдыхе от игры" value={count((p) => p.play_state === "resting")} href={list({ play: "resting" })} />
        <StatCard label="Игра закрыта до завтра" value={blocked} tone={blocked ? "warn" : undefined} href={list({ play: "blocked" })} />
      </div>

      <div className="overview-grid">
        <section className="card flush">
          <div className="card-head">
            <h2>{groupBy === "office" ? "Посещаемость по офисам" : "Посещаемость по департаментам"}</h2>
          </div>
          {groups.length === 0 ? (
            <EmptyState icon="building" title="Пока пусто" />
          ) : (
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>{groupBy === "office" ? "Офис" : "Департамент"}</th>
                    <th className="num">Сотрудников</th>
                    <th className="num">Сейчас</th>
                    <th className="num">Сегодня</th>
                    <th>Явка сегодня</th>
                  </tr>
                </thead>
                <tbody>
                  {groups.map((group) => {
                    const today = group.players.filter((p) => p.present_today).length;
                    return (
                      <tr key={group.id}>
                        <td>
                          <a href={group.href} className="player-name">
                            {group.name}
                          </a>
                          {group.sub && <span className="muted">{group.sub}</span>}
                        </td>
                        <td className="num">{group.players.length}</td>
                        <td className="num">{group.players.filter((p) => p.on_site).length}</td>
                        <td className="num">{today}</td>
                        <td>
                          <span className="meter" aria-label={percent(today, group.players.length)}>
                            <span style={{ width: group.players.length ? `${(today / group.players.length) * 100}%` : 0 }} />
                          </span>
                          <span className="muted inline meter-label">{percent(today, group.players.length)}</span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <div className="overview-side">
          <section className="card">
            <h2>Требует внимания</h2>
            {attentionItems.length === 0 ? (
              <p className="muted all-good">
                <Icon name="shield" size={16} /> Всё в порядке.
              </p>
            ) : (
              <ul className="attention-list">
                {attentionItems.map((item) => (
                  <li key={item.id}>
                    <a href={item.href}>
                      <Icon name={item.icon} size={16} />
                      <span>{item.text}</span>
                      <Icon name="chevronRight" size={14} />
                    </a>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="card">
            <h2>Самые длинные серии</h2>
            {leaders.length === 0 ? (
              <p className="muted">Серий пока нет.</p>
            ) : (
              <ol className="leaders">
                {leaders.map((p) => (
                  <li key={p.id}>
                    <a href={href([base, p.id])}>
                      <span className="player-name">{p.display_name}</span>
                      <PresenceBadge player={p} />
                    </a>
                    <b>{p.streak}</b>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      </div>
    </>
  );
}
