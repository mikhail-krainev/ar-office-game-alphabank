import { useState, type FormEvent } from "react";
import { api, type Department, type Office, type User } from "./api";
import type { DashboardActions } from "./Dashboard";

/** Departments of each office: the same team in two cities is two departments. */
export function DepartmentsPanel({ actions, players }: { actions: DashboardActions; players: User[] }) {
  return (
    <section className="card">
      <h2>Департаменты</h2>
      <p className="muted">
        Департаменты принадлежат офису. На них строятся междепартаментные задания: знакомство и бинго с коллегами из
        других отделов того же офиса.
      </p>
      {actions.offices.map((office) => (
        <OfficeDepartments key={office.id} actions={actions} office={office} players={players} />
      ))}
    </section>
  );
}

function OfficeDepartments({ actions, office, players }: { actions: DashboardActions; office: Office; players: User[] }) {
  const [name, setName] = useState("");
  const departments = actions.departments.filter((department) => department.office_id === office.id);

  async function create(event: FormEvent) {
    event.preventDefault();
    if (await actions.createDepartment(name, office.id)) {
      setName("");
    }
  }

  function rename(department: Department) {
    const next = window.prompt("Новое название департамента:", department.name);
    if (next && next.trim() !== department.name) {
      void actions.run(() => api.renameDepartment(actions.session, department.id, next));
    }
  }

  const count = (department: Department) =>
    players.filter((user) => user.department_id === department.id && !user.trip).length +
    players.filter((user) => user.trip?.department_id === department.id).length;

  return (
    <>
      <h3>
        {office.name}
        {office.city && <span className="muted"> · {office.city}</span>}
      </h3>
      {departments.length === 0 ? (
        <p className="muted">Пока нет департаментов.</p>
      ) : (
        <ul className="departments">
          {departments.map((department) => (
            <li key={department.id}>
              <span>{department.name}</span>
              <span className="muted">{count(department)} чел.</span>
              <button className="link" onClick={() => rename(department)}>
                переименовать
              </button>
            </li>
          ))}
        </ul>
      )}
      <form className="with-button" onSubmit={create}>
        <input placeholder={`Новый департамент в офисе «${office.name}»`} value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
        <button type="submit" disabled={!name.trim()}>
          Добавить
        </button>
      </form>
    </>
  );
}
