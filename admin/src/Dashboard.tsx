import { useCallback, useEffect, useState } from "react";
import type { Session } from "@heroiclabs/nakama-js";
import { api, type Department, type User } from "./api";
import { errorText, isSessionError } from "./messages";
import { CreateUserForm } from "./CreateUserForm";
import { UsersTable } from "./UsersTable";
import { DepartmentsPanel } from "./DepartmentsPanel";
import { StatsPanel } from "./StatsPanel";
import { LimitsPanel } from "./LimitsPanel";

type Section = "access" | "stats" | "limits";

export interface DashboardActions {
  session: Session;
  departments: Department[];
  /** Runs a server call, reloads the lists afterwards and reports errors. Resolves to false on error. */
  run: (action: () => Promise<unknown>) => Promise<boolean>;
  createDepartment: (name: string) => Promise<Department | null>;
  /** Shows an error of a call made outside `run`, or signs out when the session is gone. */
  report: (error: unknown) => void;
}

export function Dashboard({ session, onSessionLost }: { session: Session; onSessionLost: () => void }) {
  const [departments, setDepartments] = useState<Department[]>([]);
  const [users, setUsers] = useState<User[]>([]);
  const [error, setError] = useState("");
  const [section, setSection] = useState<Section>("access");

  const fail = useCallback(
    (e: unknown) => {
      if (isSessionError(e)) {
        onSessionLost();
      } else {
        setError(errorText(e));
      }
    },
    [onSessionLost],
  );

  const reload = useCallback(async () => {
    try {
      const [nextDepartments, nextUsers] = await Promise.all([api.listDepartments(session), api.listUsers(session)]);
      setDepartments(nextDepartments);
      setUsers(nextUsers);
    } catch (e) {
      fail(e);
    }
  }, [session, fail]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const run = useCallback(
    async (action: () => Promise<unknown>) => {
      setError("");
      try {
        await action();
        await reload();
        return true;
      } catch (e) {
        fail(e);
        return false;
      }
    },
    [reload, fail],
  );

  const createDepartment = useCallback(
    async (name: string) => {
      let created: Department | null = null;
      await run(async () => {
        created = await api.createDepartment(session, name);
      });
      return created;
    },
    [run, session],
  );

  const actions: DashboardActions = { session, departments, run, createDepartment, report: fail };
  const players = users.filter((user) => user.role === "player");

  return (
    <div className="dashboard">
      {error && (
        <p className="error banner" onClick={() => setError("")}>
          {error}
        </p>
      )}
      <nav className="sections" role="tablist">
        <button role="tab" aria-selected={section === "access"} className={section === "access" ? "tab active" : "tab"} onClick={() => setSection("access")}>
          Доступ
        </button>
        <button role="tab" aria-selected={section === "stats"} className={section === "stats" ? "tab active" : "tab"} onClick={() => setSection("stats")}>
          Статистика
        </button>
        <button role="tab" aria-selected={section === "limits"} className={section === "limits" ? "tab active" : "tab"} onClick={() => setSection("limits")}>
          Ограничения
        </button>
      </nav>
      {section === "access" && (
        <>
          <CreateUserForm actions={actions} />
          <UsersTable actions={actions} users={players} />
          <DepartmentsPanel actions={actions} players={players} />
        </>
      )}
      {section === "stats" && <StatsPanel actions={actions} />}
      {section === "limits" && <LimitsPanel actions={actions} />}
    </div>
  );
}
