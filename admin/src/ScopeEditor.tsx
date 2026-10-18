import type { Department, ManagerScope, Office } from "./api";

/**
 * Checkboxes of a manager's access: an office tick covers all its departments (also the ones created
 * later), department ticks cover single departments. Two more ticks give the rights to create and
 * to delete players there.
 */
export function ScopeEditor({
  offices,
  departments,
  scope,
  onChange,
}: {
  offices: Office[];
  departments: Department[];
  scope: ManagerScope;
  onChange: (scope: ManagerScope) => void;
}) {
  function toggle(list: string[], id: string, on: boolean): string[] {
    return on ? [...list.filter((x) => x !== id), id] : list.filter((x) => x !== id);
  }

  function toggleOffice(office: Office, on: boolean) {
    // A whole office makes its single department ticks redundant.
    const own = new Set(departments.filter((d) => d.office_id === office.id).map((d) => d.id));
    onChange({
      ...scope,
      offices: toggle(scope.offices, office.id, on),
      departments: on ? scope.departments.filter((id) => !own.has(id)) : scope.departments,
    });
  }

  return (
    <div className="scope-editor">
      <div className="scope-offices">
        {offices.map((office) => {
          const whole = scope.offices.includes(office.id);
          const own = departments.filter((d) => d.office_id === office.id);
          return (
            <div key={office.id} className="scope-office">
              <label className="check scope-office-head">
                <input type="checkbox" checked={whole} onChange={(e) => toggleOffice(office, e.target.checked)} />
                <span>
                  <b>{office.name}</b>
                  {office.city && <span className="muted"> · {office.city}</span>}
                  <span className="muted"> — весь офис</span>
                </span>
              </label>
              {own.length === 0 ? (
                <p className="muted">Нет департаментов.</p>
              ) : (
                own.map((department) => (
                  <label key={department.id} className="check">
                    <input
                      type="checkbox"
                      checked={whole || scope.departments.includes(department.id)}
                      disabled={whole}
                      onChange={(e) => onChange({ ...scope, departments: toggle(scope.departments, department.id, e.target.checked) })}
                    />
                    {department.name}
                  </label>
                ))
              )}
            </div>
          );
        })}
      </div>
      <div className="scope-rights">
        <label className="check">
          <input type="checkbox" checked={scope.can_create} onChange={(e) => onChange({ ...scope, can_create: e.target.checked })} />
          Может создавать сотрудников и привязывать их к офису и департаменту
        </label>
        <label className="check">
          <input type="checkbox" checked={scope.can_delete} onChange={(e) => onChange({ ...scope, can_delete: e.target.checked })} />
          Может удалять сотрудников
        </label>
      </div>
    </div>
  );
}

export const EMPTY_SCOPE: ManagerScope = { offices: [], departments: [], can_create: false, can_delete: false };

export function scopeIsEmpty(scope: ManagerScope): boolean {
  return scope.offices.length === 0 && scope.departments.length === 0;
}

/** "Екатеринбург (весь офис), Дизайн · Москва" */
export function scopeLabel(scope: ManagerScope, offices: Office[], departments: Department[]): string {
  const officeName = (id: string) => offices.find((o) => o.id === id)?.name ?? "—";
  const parts = [
    ...scope.offices.map((id) => `${officeName(id)} (весь офис)`),
    ...scope.departments.map((id) => {
      const department = departments.find((d) => d.id === id);
      return department ? `${department.name} · ${officeName(department.office_id)}` : "—";
    }),
  ];
  return parts.join(", ");
}
