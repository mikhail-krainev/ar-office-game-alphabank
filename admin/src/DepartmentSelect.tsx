import { useState } from "react";
import type { DashboardActions } from "./Dashboard";
import { Dropdown } from "./Dropdown";

const NEW_DEPARTMENT = "__new__";

/**
 * Department picker for one office, with an inline "new department" option (created in that office).
 * The empty value means none chosen.
 */
export function DepartmentSelect({
  actions,
  officeId,
  value,
  onChange,
}: {
  actions: DashboardActions;
  officeId: string;
  value: string;
  onChange: (id: string) => void;
}) {
  const [creating, setCreating] = useState(false);
  const [name, setName] = useState("");

  async function create() {
    const department = await actions.createDepartment(name, officeId);
    if (department) {
      onChange(department.id);
      setCreating(false);
      setName("");
    }
  }

  if (creating) {
    return (
      <span className="inline-create">
        <input autoFocus placeholder="Название департамента" value={name} onChange={(e) => setName(e.target.value)} />
        <button type="button" onClick={create} disabled={!name.trim()}>
          Создать
        </button>
        <button type="button" className="link" onClick={() => setCreating(false)}>
          Отмена
        </button>
      </span>
    );
  }

  if (!officeId) {
    return <Dropdown value="" placeholder="Сначала выберите офис" options={[]} onChange={() => undefined} />;
  }

  return (
    <Dropdown
      value={value}
      placeholder="Выберите департамент"
      options={[
        ...actions.departments
          .filter((department) => department.office_id === officeId)
          .map((department) => ({ value: department.id, label: department.name })),
        { value: NEW_DEPARTMENT, label: "+ Новый департамент…", action: true },
      ]}
      onChange={(id) => (id === NEW_DEPARTMENT ? setCreating(true) : onChange(id))}
    />
  );
}
