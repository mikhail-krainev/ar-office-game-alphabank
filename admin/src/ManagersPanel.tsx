import { useCallback, useEffect, useState, type FormEvent } from "react";
import { api, type Manager, type ManagerScope } from "./api";
import type { DashboardActions } from "./Dashboard";
import { formatDateTime } from "./format";
import { generatePassword } from "./password";
import { EMPTY_SCOPE, ScopeEditor, scopeIsEmpty, scopeLabel } from "./ScopeEditor";

/**
 * Managers (department heads): the admin gives each one offices and departments to watch and,
 * optionally, the rights to create and delete players there. Managers sign in to their own panel.
 */
export function ManagersPanel({ actions }: { actions: DashboardActions }) {
  const { session, run, report } = actions;
  const [managers, setManagers] = useState<Manager[] | null>(null);
  const [editing, setEditing] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setManagers(await api.listManagers(session));
    } catch (e) {
      report(e);
    }
  }, [session, report]);

  useEffect(() => {
    void load();
  }, [load]);

  const runAndReload = useCallback(
    async (action: () => Promise<unknown>) => {
      const ok = await run(action);
      await load();
      return ok;
    },
    [run, load],
  );

  async function resetPassword(manager: Manager) {
    const password = window.prompt(`Новый пароль для ${manager.username} (от 8 символов):`, generatePassword());
    if (password && (await run(() => api.setPassword(session, manager.id, password)))) {
      window.alert(`Пароль изменён.\nлогин: ${manager.username}\nпароль: ${password}\nСтарые сессии завершены.`);
    }
  }

  function remove(manager: Manager) {
    if (window.confirm(`Удалить руководителя ${manager.username}? Сотрудники и их прогресс останутся.`)) {
      void runAndReload(() => api.deleteUser(session, manager.id));
    }
  }

  return (
    <>
      <CreateManagerForm actions={actions} onCreated={load} />
      <section className="card">
        <h2>Руководители ({managers?.length ?? 0})</h2>
        <p className="muted">
          Руководитель входит в свою панель с тем же адресом и видит статистику только отмеченных офисов и
          департаментов. Права можно изменить или отобрать в любой момент: следующий же запрос руководителя пойдёт по
          новым правам.
        </p>
        {managers === null ? (
          <p className="muted">Загрузка…</p>
        ) : managers.length === 0 ? (
          <p className="muted">Пока нет руководителей.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Руководитель</th>
                  <th>Доступ</th>
                  <th>Права</th>
                  <th>Создан</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {managers.map((manager) =>
                  editing === manager.id ? (
                    <tr key={manager.id}>
                      <td colSpan={5}>
                        <EditScope
                          actions={actions}
                          manager={manager}
                          onSave={async (scope) => {
                            if (await runAndReload(() => api.updateManager(session, manager.id, scope))) {
                              setEditing(null);
                            }
                          }}
                          onCancel={() => setEditing(null)}
                        />
                      </td>
                    </tr>
                  ) : (
                    <tr key={manager.id}>
                      <td className="nowrap">
                        <div className="player-name">{manager.display_name}</div>
                        <code className="muted">{manager.username}</code>
                      </td>
                      <td>{scopeLabel(manager.scope, actions.offices, actions.departments)}</td>
                      <td className="nowrap">
                        {manager.scope.can_create && <span className="badge present">создаёт</span>}{" "}
                        {manager.scope.can_delete && <span className="badge missed">удаляет</span>}
                        {!manager.scope.can_create && !manager.scope.can_delete && <span className="muted">только просмотр</span>}
                      </td>
                      <td className="nowrap">{formatDateTime(manager.created_at)}</td>
                      <td className="actions">
                        <div className="row-actions">
                          <button className="secondary" onClick={() => setEditing(manager.id)}>
                            Доступ и права
                          </button>
                          <button className="secondary" onClick={() => void resetPassword(manager)}>
                            Пароль
                          </button>
                          <button className="danger" onClick={() => remove(manager)}>
                            Удалить
                          </button>
                        </div>
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

function EditScope({
  actions,
  manager,
  onSave,
  onCancel,
}: {
  actions: DashboardActions;
  manager: Manager;
  onSave: (scope: ManagerScope) => Promise<void>;
  onCancel: () => void;
}) {
  const [scope, setScope] = useState<ManagerScope>(manager.scope);
  return (
    <div className="scope-edit">
      <h3>
        {manager.display_name} <code className="muted">{manager.username}</code>
      </h3>
      <ScopeEditor offices={actions.offices} departments={actions.departments} scope={scope} onChange={setScope} />
      <div className="row-actions">
        <button onClick={() => void onSave(scope)} disabled={scopeIsEmpty(scope)}>
          Сохранить
        </button>
        <button className="secondary" onClick={onCancel}>
          Отмена
        </button>
      </div>
    </div>
  );
}

function CreateManagerForm({ actions, onCreated }: { actions: DashboardActions; onCreated: () => Promise<void> }) {
  const [displayName, setDisplayName] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState(() => generatePassword());
  const [scope, setScope] = useState<ManagerScope>(EMPTY_SCOPE);
  const [issued, setIssued] = useState<{ name: string; username: string; password: string } | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const manager = { username, password, display_name: displayName, scope };
    if (await actions.run(() => api.createManager(actions.session, manager))) {
      setIssued({ name: displayName.trim(), username: username.trim().toLowerCase(), password });
      setDisplayName("");
      setUsername("");
      setPassword(generatePassword());
      setScope(EMPTY_SCOPE);
      await onCreated();
    }
  }

  return (
    <section className="card">
      <h2>Назначить руководителя</h2>
      <form onSubmit={submit}>
        <div className="grid-form">
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
        </div>
        <h3>Доступ к офисам и департаментам</h3>
        <ScopeEditor offices={actions.offices} departments={actions.departments} scope={scope} onChange={setScope} />
        <button type="submit" disabled={scopeIsEmpty(scope)}>
          Создать руководителя
        </button>
      </form>
      {issued && (
        <div className="issued">
          <p>
            Руководитель <b>{issued.name}</b> создан. Передайте данные для входа в панель:
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
