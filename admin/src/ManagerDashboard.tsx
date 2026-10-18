import { useCallback, useEffect, useState } from "react";
import type { Session } from "@heroiclabs/nakama-js";
import { ApiError, managerApi, type ManagerProfile, type PlayerSummary } from "./api";
import type { DashboardActions } from "./Dashboard";
import { errorText, isSessionError } from "./messages";
import { CreateUserForm } from "./CreateUserForm";
import { StatsPanel } from "./StatsPanel";
import { scopeLabel } from "./ScopeEditor";
import { formatDateTime } from "./format";

type Section = "stats" | "staff";

/**
 * The manager's panel, separate from the admin's: statistics of the offices and departments the
 * admin ticked and, with the rights, creating and deleting players there. Every call goes to a
 * manager_* RPC that checks the scope again, so a right the admin took away stops at once; the
 * panel then reloads the scope and hides the buttons.
 */
export function ManagerDashboard({ session, onSessionLost }: { session: Session; onSessionLost: () => void }) {
  const [profile, setProfile] = useState<ManagerProfile | null>(null);
  const [error, setError] = useState("");
  const [section, setSection] = useState<Section>("stats");
  const [staffVersion, setStaffVersion] = useState(0);

  const reload = useCallback(async () => {
    try {
      setProfile(await managerApi.profile(session));
    } catch (e) {
      if (isSessionError(e)) {
        onSessionLost();
      } else {
        setError(errorText(e));
      }
    }
  }, [session, onSessionLost]);

  const fail = useCallback(
    (e: unknown) => {
      if (isSessionError(e)) {
        onSessionLost();
        return;
      }
      setError(errorText(e));
      if (e instanceof ApiError && (e.key === "manager_right_missing" || e.key === "out_of_scope")) {
        // The admin changed the rights meanwhile.
        void reload();
      }
    },
    [onSessionLost, reload],
  );

  useEffect(() => {
    void reload();
  }, [reload]);

  const run = useCallback(
    async (action: () => Promise<unknown>) => {
      setError("");
      try {
        await action();
        await reload();
        setStaffVersion((v) => v + 1);
        return true;
      } catch (e) {
        fail(e);
        return false;
      }
    },
    [reload, fail],
  );

  const offices = profile?.offices ?? [];
  const departments = profile?.departments ?? [];
  const officeNames = profile?.office_names;
  const officeName = useCallback((id: string) => officeNames?.[id] ?? "—", [officeNames]);
  const departmentName = useCallback((id: string) => departments.find((d) => d.id === id)?.name ?? "—", [departments]);
  const loadStats = useCallback(() => managerApi.statsOverview(session), [session]);
  const loadPlayerStats = useCallback((userId: string) => managerApi.playerStats(session, userId), [session]);

  if (!profile) {
    return <p className="muted">{error || "Загрузка…"}</p>;
  }

  const actions: DashboardActions = {
    session,
    offices,
    departments,
    officeName,
    departmentName,
    run,
    createDepartment: null,
    loadStats,
    loadPlayerStats,
    report: fail,
  };
  const { scope } = profile;

  return (
    <div className="dashboard">
      <section className="card manager-head">
        <h2>{profile.display_name || "Руководитель"}</h2>
        <p className="muted">
          Доступ: {scopeLabel(scope, offices, departments)}. Права:{" "}
          {[scope.can_create && "создание сотрудников", scope.can_delete && "удаление сотрудников"].filter(Boolean).join(", ") ||
            "только просмотр"}
          .
        </p>
      </section>
      {error && (
        <p className="error banner" onClick={() => setError("")}>
          {error}
        </p>
      )}
      <nav className="sections" role="tablist">
        <button role="tab" aria-selected={section === "stats"} className={section === "stats" ? "tab active" : "tab"} onClick={() => setSection("stats")}>
          Статистика
        </button>
        <button role="tab" aria-selected={section === "staff"} className={section === "staff" ? "tab active" : "tab"} onClick={() => setSection("staff")}>
          Сотрудники
        </button>
      </nav>
      {section === "stats" && <StatsPanel actions={actions} />}
      {section === "staff" && (
        <>
          {scope.can_create && <CreateUserForm actions={actions} create={(user) => managerApi.createUser(session, user)} />}
          <StaffTable key={staffVersion} actions={actions} canDelete={scope.can_delete} />
        </>
      )}
    </div>
  );
}

function StaffTable({ actions, canDelete }: { actions: DashboardActions; canDelete: boolean }) {
  const { session, run, report, loadStats, officeName, departmentName } = actions;
  const [players, setPlayers] = useState<PlayerSummary[] | null>(null);

  useEffect(() => {
    loadStats().then(setPlayers, report);
  }, [loadStats, report]);

  function remove(player: PlayerSummary) {
    if (window.confirm(`Удалить аккаунт ${player.username} (${player.display_name})? Прогресс, монеты и история удалятся без возврата.`)) {
      void run(() => managerApi.deleteUser(session, player.id));
    }
  }

  if (players === null) {
    return <p className="muted">Загрузка…</p>;
  }
  return (
    <section className="card">
      <h2>Сотрудники ({players.length})</h2>
      {players.length === 0 ? (
        <p className="muted">В ваших департаментах пока никого.</p>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Сотрудник</th>
                <th>Офис и департамент</th>
                <th>Создан</th>
                {canDelete && <th />}
              </tr>
            </thead>
            <tbody>
              {players.map((player) => (
                <tr key={player.id} className={player.banned ? "banned" : ""}>
                  <td className="nowrap">
                    <div className="player-name">{player.display_name}</div>
                    <code className="muted">{player.username}</code>
                  </td>
                  <td>
                    {officeName(player.office_id)}
                    <div className="muted">{departmentName(player.department_id)}</div>
                    {player.current_office_id !== player.office_id && (
                      <span className="badge soft">сейчас в офисе: {officeName(player.current_office_id)}</span>
                    )}
                  </td>
                  <td className="nowrap">{formatDateTime(player.created_at)}</td>
                  {canDelete && (
                    <td className="actions">
                      <button className="danger" onClick={() => remove(player)}>
                        Удалить
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
