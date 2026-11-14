import { useMemo, useState, type FormEvent } from "react";
import { api, type Manager, type ManagerScope } from "./api";
import type { DashboardActions } from "./actions";
import { IssuedCredentials, PasswordInput, ResetPasswordForm, type Issued } from "./Credentials";
import { useDialogs } from "./Dialogs";
import { FilterBar, matches, useFilters } from "./FilterBar";
import { formatDateTime } from "./format";
import { Icon } from "./Icon";
import { generatePassword } from "./password";
import { href, navigate } from "./router";
import { EMPTY_SCOPE, ScopeEditor, scopeIsEmpty, scopeLabel } from "./ScopeEditor";
import { Drawer, EmptyState, Loading, PageHeader } from "./ui";

const DEFAULT_FILTERS = { q: "", office: "", rights: "" };

type Rights = "create" | "delete" | "view";
const RIGHTS_LABELS: Record<Rights, string> = { create: "создаёт сотрудников", delete: "удаляет сотрудников", view: "только просмотр" };

function hasRights(scope: ManagerScope, rights: string): boolean {
  if (rights === "create") {
    return scope.can_create;
  }
  if (rights === "delete") {
    return scope.can_delete;
  }
  return rights !== "view" || (!scope.can_create && !scope.can_delete);
}

/**
 * Managers (department heads): the admin gives each one offices and departments to watch and,
 * optionally, the rights to create and delete players there. "#/managers/<id>" opens one manager,
 * "#/managers?new=1" the form of a new one.
 */
export function ManagersPage({
  actions,
  managers,
  selectedId,
  creating,
  onChanged,
}: {
  actions: DashboardActions;
  managers: Manager[] | null;
  selectedId: string;
  creating: boolean;
  onChanged: () => Promise<void>;
}) {
  const { offices, departments } = actions;
  const { values, set, reset, active } = useFilters("managers", DEFAULT_FILTERS);
  const close = () => navigate(href(["managers"]));

  const visible = useMemo(() => {
    const inOffice = (scope: ManagerScope, officeId: string) =>
      scope.offices.includes(officeId) || scope.departments.some((id) => departments.find((d) => d.id === id)?.office_id === officeId);
    return (managers ?? [])
      .filter((m) => !values.office || inOffice(m.scope, values.office))
      .filter((m) => !values.rights || hasRights(m.scope, values.rights))
      .filter((m) => matches(values.q, m.display_name, m.username, scopeLabel(m.scope, offices, departments)));
  }, [managers, values, offices, departments]);
  const selected = managers?.find((m) => m.id === selectedId);

  return (
    <>
      <PageHeader
        title="Руководители"
        actions={
          <button type="button" onClick={() => navigate(href(["managers"], { new: "1" }))}>
            <Icon name="plus" size={16} /> Назначить руководителя
          </button>
        }
      />
      <section className="card flush">
        <FilterBar
          query={values.q}
          onQuery={(text) => set("q", text)}
          placeholder="Имя, логин или офис"
          filters={[
            { key: "office", label: "Офис", allLabel: "все", options: offices.map((o) => ({ value: o.id, label: o.name })) },
            { key: "rights", label: "Права", allLabel: "любые", options: Object.entries(RIGHTS_LABELS).map(([value, label]) => ({ value, label })) },
          ]}
          values={values}
          onChange={(key, value) => set(key as keyof typeof DEFAULT_FILTERS, value)}
          onReset={reset}
          active={active}
          shown={visible.length}
          total={managers?.length ?? 0}
          noun={["руководитель", "руководителя", "руководителей"]}
        />
        {managers === null ? (
          <Loading />
        ) : managers.length === 0 ? (
          <EmptyState icon="shield" title="Пока нет руководителей">
            <button type="button" onClick={() => navigate(href(["managers"], { new: "1" }))}>
              Назначить первого
            </button>
          </EmptyState>
        ) : visible.length === 0 ? (
          <EmptyState title="Никого не найдено">
            <button type="button" className="link" onClick={reset}>
              Сбросить фильтры
            </button>
          </EmptyState>
        ) : (
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Руководитель</th>
                  <th>Доступ</th>
                  <th>Права</th>
                  <th>Создан</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((manager) => {
                  const to = href(["managers", manager.id]);
                  return (
                    <tr key={manager.id} className="clickable" onClick={() => navigate(to)}>
                      <td>
                        <a className="row-link" href={to} onClick={(e) => e.stopPropagation()}>
                          <span className="avatar small" aria-hidden="true">
                            {manager.display_name.charAt(0).toUpperCase() || "?"}
                          </span>
                          <span>
                            <span className="player-name">{manager.display_name}</span>
                            <code className="muted">{manager.username}</code>
                          </span>
                        </a>
                      </td>
                      <td>{scopeLabel(manager.scope, offices, departments)}</td>
                      <td>
                        <RightsBadges scope={manager.scope} />
                      </td>
                      <td className="nowrap">{formatDateTime(manager.created_at)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {creating && (
        <Drawer title="Назначить руководителя" onClose={close} wide>
          <CreateManagerForm actions={actions} onCreated={onChanged} onClose={close} />
        </Drawer>
      )}
      {selectedId && managers !== null && (
        <Drawer title={selected ? selected.display_name : "Руководитель не найден"} onClose={close} wide>
          {selected ? <ManagerDetails actions={actions} manager={selected} onChanged={onChanged} onClose={close} /> : <p className="muted">Возможно, его уже удалили.</p>}
        </Drawer>
      )}
    </>
  );
}

function RightsBadges({ scope }: { scope: ManagerScope }) {
  if (!scope.can_create && !scope.can_delete) {
    return <span className="badge muted-badge">только просмотр</span>;
  }
  return (
    <div className="badge-row">
      {scope.can_create && <span className="badge present">создаёт</span>}
      {scope.can_delete && <span className="badge missed">удаляет</span>}
    </div>
  );
}

function ManagerDetails({
  actions,
  manager,
  onChanged,
  onClose,
}: {
  actions: DashboardActions;
  manager: Manager;
  onChanged: () => Promise<void>;
  onClose: () => void;
}) {
  const { session, run } = actions;
  const { confirm, notify } = useDialogs();
  const [scope, setScope] = useState<ManagerScope>(manager.scope);
  const [resetting, setResetting] = useState(false);
  const changed = JSON.stringify(scope) !== JSON.stringify(manager.scope);

  async function save() {
    if (await run(() => api.updateManager(session, manager.id, scope))) {
      await onChanged();
      notify("Доступ и права сохранены.");
    }
  }

  async function remove() {
    const ok = await confirm({
      title: "Удалить руководителя?",
      text: `Аккаунт ${manager.username} удалится. Сотрудники и их прогресс останутся.`,
      confirmLabel: "Удалить",
      danger: true,
    });
    if (ok && (await run(() => api.deleteUser(session, manager.id)))) {
      await onChanged();
      notify(`Руководитель ${manager.username} удалён.`);
      onClose();
    }
  }

  if (resetting) {
    return (
      <ResetPasswordForm
        name={manager.display_name}
        username={manager.username}
        save={(password) => run(() => api.setPassword(session, manager.id, password))}
        onDone={() => setResetting(false)}
      />
    );
  }

  return (
    <div className="stack-form">
      <p className="muted">
        <code>{manager.username}</code> · создан {formatDateTime(manager.created_at)}
      </p>
      <h3>Доступ к офисам и департаментам</h3>
      <ScopeEditor offices={actions.offices} departments={actions.departments} scope={scope} onChange={setScope} />
      <div className="form-actions">
        <button type="button" onClick={() => void save()} disabled={!changed || scopeIsEmpty(scope)}>
          Сохранить
        </button>
        <button type="button" className="secondary" disabled={!changed} onClick={() => setScope(manager.scope)}>
          Отменить изменения
        </button>
      </div>
      <h3>Аккаунт</h3>
      <div className="form-actions">
        <button type="button" className="secondary" onClick={() => setResetting(true)}>
          <Icon name="key" size={16} /> Сменить пароль
        </button>
        <button type="button" className="danger" onClick={() => void remove()}>
          <Icon name="trash" size={16} /> Удалить руководителя
        </button>
      </div>
    </div>
  );
}

function CreateManagerForm({ actions, onCreated, onClose }: { actions: DashboardActions; onCreated: () => Promise<void>; onClose: () => void }) {
  const [displayName, setDisplayName] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState(() => generatePassword());
  const [scope, setScope] = useState<ManagerScope>(EMPTY_SCOPE);
  const [issued, setIssued] = useState<Issued | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const manager = { username, password, display_name: displayName, scope };
    if (await actions.run(() => api.createManager(actions.session, manager))) {
      setIssued({ name: displayName.trim(), username: username.trim().toLowerCase(), password });
      await onCreated();
    }
  }

  if (issued) {
    return <IssuedCredentials issued={issued} text="Руководитель создан:" onDone={onClose} />;
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <div className="grid-form">
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
        </label>
        <label>
          Пароль
          <PasswordInput value={password} onChange={setPassword} />
        </label>
      </div>
      <h3>Доступ к офисам и департаментам</h3>
      <ScopeEditor offices={actions.offices} departments={actions.departments} scope={scope} onChange={setScope} />
      <div className="form-actions">
        <button type="submit" disabled={scopeIsEmpty(scope)}>
          Создать руководителя
        </button>
        <button type="button" className="secondary" onClick={onClose}>
          Отмена
        </button>
      </div>
    </form>
  );
}
