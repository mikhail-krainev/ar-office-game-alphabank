import { useState, type FormEvent } from "react";
import type { NewUser } from "./api";
import type { DashboardActions } from "./actions";
import { IssuedCredentials, PasswordInput, type Issued } from "./Credentials";
import { DepartmentSelect } from "./DepartmentSelect";
import { OfficeSelect } from "./OfficeSelect";
import { generatePassword } from "./password";

/** Creating an account is what activates a player: without it the game refuses to sign in. */
export function CreateUserForm({
  actions,
  create,
  onClose,
}: {
  actions: DashboardActions;
  create: (user: NewUser) => Promise<unknown>;
  onClose: () => void;
}) {
  const [displayName, setDisplayName] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState(() => generatePassword());
  // One office: nothing to choose.
  const [officeId, setOfficeId] = useState(actions.offices.length === 1 ? actions.offices[0].id : "");
  const [departmentId, setDepartmentId] = useState("");
  const [issued, setIssued] = useState<Issued | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const user = { username, password, display_name: displayName, office_id: officeId, department_id: departmentId };
    if (await actions.run(() => create(user))) {
      setIssued({ name: displayName.trim(), username: username.trim().toLowerCase(), password });
      setDisplayName("");
      setUsername("");
      setPassword(generatePassword());
    }
  }

  if (issued) {
    return (
      <>
        <IssuedCredentials issued={issued} text="Аккаунт создан:" />
        <div className="form-actions">
          <button type="button" onClick={() => setIssued(null)}>
            Добавить ещё
          </button>
          <button type="button" className="secondary" onClick={onClose}>
            Закрыть
          </button>
        </div>
      </>
    );
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <label>
        Имя и фамилия
        <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={60} required autoFocus />
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
        <span className="hint">3–32 символа: латиница, цифры, точка, _ или -.</span>
      </label>
      <label>
        Пароль
        <PasswordInput value={password} onChange={setPassword} />
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
      <div className="form-actions">
        <button type="submit" disabled={!officeId || !departmentId}>
          Создать аккаунт
        </button>
        <button type="button" className="secondary" onClick={onClose}>
          Отмена
        </button>
      </div>
    </form>
  );
}
