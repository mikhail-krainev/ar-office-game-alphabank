import { useMemo, useState, type FormEvent } from "react";
import { api, type Department } from "./api";
import type { DashboardActions } from "./actions";
import { useDialogs } from "./Dialogs";
import { FilterBar, matches, useFilters } from "./FilterBar";
import { Icon } from "./Icon";
import { OfficeSelect } from "./OfficeSelect";
import { href, navigate } from "./router";
import { Drawer, EmptyState, PageHeader } from "./ui";

const DEFAULT_FILTERS = { q: "", office: "", size: "" };

/** Players counted in a department today: its own (not away on a trip) and the ones on a trip there. */
export function departmentCount(actions: DashboardActions, department: Department): number {
  return (actions.players ?? []).filter(
    (p) => (p.department_id === department.id && !p.trip) || p.trip?.department_id === department.id,
  ).length;
}

/** All departments of all offices: the same team in two cities is two departments. */
export function DepartmentsPage({ actions, creating }: { actions: DashboardActions; creating: boolean }) {
  const { departments, offices, officeName } = actions;
  const { values, set, reset, active } = useFilters("departments", DEFAULT_FILTERS);
  const close = () => navigate(href(["departments"]));

  const visible = useMemo(
    () =>
      departments
        .filter((d) => !values.office || d.office_id === values.office)
        .filter((d) => !values.size || (values.size === "empty" ? departmentCount(actions, d) === 0 : departmentCount(actions, d) > 0))
        .filter((d) => matches(values.q, d.name, officeName(d.office_id)))
        .sort((a, b) => officeName(a.office_id).localeCompare(officeName(b.office_id), "ru") || a.name.localeCompare(b.name, "ru")),
    [departments, values, officeName, actions],
  );

  return (
    <>
      <PageHeader
        title="Департаменты"
        actions={
          <button type="button" onClick={() => navigate(href(["departments"], { new: "1" }))}>
            <Icon name="plus" size={16} /> Новый департамент
          </button>
        }
      />
      <section className="card flush">
        <FilterBar
          query={values.q}
          onQuery={(text) => set("q", text)}
          placeholder="Название департамента"
          filters={[
            ...(offices.length > 1 ? [{ key: "office", label: "Офис", allLabel: "все", options: offices.map((o) => ({ value: o.id, label: o.name })) }] : []),
            {
              key: "size",
              label: "Сотрудники",
              allLabel: "любые",
              options: [
                { value: "filled", label: "есть сотрудники" },
                { value: "empty", label: "пустые" },
              ],
            },
          ]}
          values={values}
          onChange={(key, value) => set(key as keyof typeof DEFAULT_FILTERS, value)}
          onReset={reset}
          active={active}
          shown={visible.length}
          total={departments.length}
          noun={["департамент", "департамента", "департаментов"]}
        />
        <DepartmentsTable actions={actions} departments={visible} showOffice={offices.length > 1} onReset={reset} />
      </section>
      {creating && (
        <Drawer title="Новый департамент" onClose={close}>
          <CreateDepartmentForm actions={actions} officeId={values.office} onDone={close} />
        </Drawer>
      )}
    </>
  );
}

export function DepartmentsTable({
  actions,
  departments,
  showOffice,
  onReset,
}: {
  actions: DashboardActions;
  departments: Department[];
  showOffice: boolean;
  onReset?: () => void;
}) {
  const [renaming, setRenaming] = useState<Department | null>(null);

  if (departments.length === 0) {
    return (
      <EmptyState icon="layers" title="Департаментов нет">
        {onReset && (
          <button type="button" className="link" onClick={onReset}>
            Сбросить фильтры
          </button>
        )}
      </EmptyState>
    );
  }
  return (
    <>
      <div className="table-wrap">
        <table className="data-table">
          <thead>
            <tr>
              <th>Департамент</th>
              {showOffice && <th>Офис</th>}
              <th className="num">Сотрудников</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {departments.map((department) => {
              const count = departmentCount(actions, department);
              return (
                <tr key={department.id}>
                  <td className="player-name">{department.name}</td>
                  {showOffice && (
                    <td>
                      <a href={href(["offices", department.office_id])}>{actions.officeName(department.office_id)}</a>
                    </td>
                  )}
                  <td className="num">
                    {count > 0 ? <a href={href([actions.role === "admin" ? "players" : "staff"], { department: department.id, office: department.office_id })}>{count}</a> : <span className="muted">0</span>}
                  </td>
                  <td className="actions">
                    {actions.createDepartment && (
                      <button type="button" className="secondary small" onClick={() => setRenaming(department)}>
                        <Icon name="edit" size={14} /> Переименовать
                      </button>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {renaming && (
        <Drawer title="Переименовать департамент" onClose={() => setRenaming(null)}>
          <RenameDepartmentForm actions={actions} department={renaming} onDone={() => setRenaming(null)} />
        </Drawer>
      )}
    </>
  );
}

function RenameDepartmentForm({ actions, department, onDone }: { actions: DashboardActions; department: Department; onDone: () => void }) {
  const [name, setName] = useState(department.name);
  const { notify } = useDialogs();

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (await actions.run(() => api.renameDepartment(actions.session, department.id, name.trim()))) {
      notify("Департамент переименован.");
      onDone();
    }
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <p className="muted">Офис «{actions.officeName(department.office_id)}».</p>
      <label>
        Название
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} required autoFocus />
      </label>
      <div className="form-actions">
        <button type="submit" disabled={!name.trim() || name.trim() === department.name}>
          Сохранить
        </button>
        <button type="button" className="secondary" onClick={onDone}>
          Отмена
        </button>
      </div>
    </form>
  );
}

export function CreateDepartmentForm({ actions, officeId, onDone }: { actions: DashboardActions; officeId: string; onDone: () => void }) {
  const [office, setOffice] = useState(officeId || (actions.offices.length === 1 ? actions.offices[0].id : ""));
  const [name, setName] = useState("");
  const { notify } = useDialogs();

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (await actions.createDepartment?.(name, office)) {
      notify(`Департамент «${name.trim()}» создан.`);
      onDone();
    }
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <label>
        Офис
        <OfficeSelect actions={actions} value={office} onChange={setOffice} />
      </label>
      <label>
        Название
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} required autoFocus />
      </label>
      <div className="form-actions">
        <button type="submit" disabled={!office || !name.trim()}>
          Создать
        </button>
        <button type="button" className="secondary" onClick={onDone}>
          Отмена
        </button>
      </div>
    </form>
  );
}
