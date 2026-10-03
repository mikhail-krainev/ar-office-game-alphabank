import type { DashboardActions } from "./Dashboard";
import { Dropdown } from "./Dropdown";

/**
 * Office picker. The empty value means none chosen; `except` hides one office (the home office of a
 * trip); `compact` shows names without the city (table cells).
 */
export function OfficeSelect({
  actions,
  value,
  onChange,
  except,
  compact,
}: {
  actions: DashboardActions;
  value: string;
  onChange: (id: string) => void;
  except?: string;
  compact?: boolean;
}) {
  return (
    <Dropdown
      value={value}
      placeholder="Выберите офис"
      options={actions.offices
        .filter((office) => office.id !== except)
        .map((office) => ({ value: office.id, label: office.city && !compact ? `${office.name} · ${office.city}` : office.name }))}
      onChange={onChange}
    />
  );
}
