import { useState, type FormEvent } from "react";
import { api } from "./api";
import type { DashboardActions } from "./Dashboard";
import { DepartmentSelect } from "./DepartmentSelect";
import { OfficeSelect } from "./OfficeSelect";
import { generatePassword } from "./password";

interface Issued {
  name: string;
  username: string;
  password: string;
}

/** Creating an account is what activates a player: without it the game refuses to sign in. */
export function CreateUserForm({ actions }: { actions: DashboardActions }) {
  const [displayName, setDisplayName] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState(() => generatePassword());
  const [officeId, setOfficeId] = useState("");
  const [departmentId, setDepartmentId] = useState("");
  const [issued, setIssued] = useState<Issued | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const user = { username, password, display_name: displayName, office_id: officeId, department_id: departmentId };
    const ok = await actions.run(() => api.createUser(actions.session, user));
    if (ok) {
      setIssued({ name: displayName.trim(), username: username.trim().toLowerCase(), password });
      setDisplayName("");
      setUsername("");
      setPassword(generatePassword());
    }
  }

  return (
    <section className="card">
      <h2>Выдать доступ</h2>
      <form className="grid-form" onSubmit={submit}>
        <label>
          Имя и фамилия
          <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={60} required />
        </label>
        <label>
          Логин
          <input
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            pattern="[A-Za-z0-9][A-Za-z0-9._\-]{2,31}"
            title="3–32 символа: латиница, цифры, точка, _ или -"
            autoCapitalize="none"
            required
          />
        </label>
        <label>
          Пароль
          <span className="with-button">
            <input value={password} onChange={(e) => setPassword(e.target.value)} minLength={8} required />
            <button type="button" className="secondary" onClick={() => setPassword(generatePassword())}>
              ↻
            </button>
          </span>
        </label>
        <label>
          Офис
          <OfficeSelect
            actions={actions}
            value={officeId}
            onChange={(id) => {
              setOfficeId(id);
              setDepartmentId("");
            }}
          />
        </label>
        <label>
          Департамент
          <DepartmentSelect actions={actions} officeId={officeId} value={departmentId} onChange={setDepartmentId} />
        </label>
        <button type="submit" disabled={!officeId || !departmentId}>
          Создать аккаунт
        </button>
      </form>
      {issued && (
        <div className="issued">
          <p>
            Аккаунт для <b>{issued.name}</b> создан. Передайте данные для входа:
          </p>
          <code>
            логин: {issued.username}
            <br />
            пароль: {issued.password}
          </code>
          <button className="link" onClick={() => setIssued(null)}>
            Скрыть
          </button>
        </div>
      )}
    </section>
  );
}
