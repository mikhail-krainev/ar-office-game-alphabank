import { useState, type FormEvent } from "react";
import { api, type PlayerSummary, type Trip } from "./api";
import type { DashboardActions } from "./actions";
import { DepartmentSelect } from "./DepartmentSelect";
import { OfficeSelect } from "./OfficeSelect";

/** "Москва · Дизайн, до 16.10.2026" */
export function tripLabel(actions: DashboardActions, trip: Trip): string {
  const [year, month, day] = trip.until.split("-");
  return `${actions.officeName(trip.office_id)} · ${actions.departmentName(trip.department_id)}, до ${day}.${month}.${year}`;
}

function today(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/**
 * Business trip: until its last day the player counts in another office and department: checks in
 * there, meets its colleagues and follows its limits. The parking draw and the statistics stay home.
 */
export function TripForm({
  actions,
  player,
  onDone,
}: {
  actions: DashboardActions;
  player: Pick<PlayerSummary, "id" | "display_name" | "office_id" | "trip">;
  onDone: () => void;
}) {
  const [officeId, setOfficeId] = useState(player.trip?.office_id ?? "");
  const [departmentId, setDepartmentId] = useState(player.trip?.department_id ?? "");
  const [until, setUntil] = useState(player.trip?.until ?? "");

  async function submit(event: FormEvent) {
    event.preventDefault();
    const trip = { office_id: officeId, department_id: departmentId, until };
    if (await actions.run(() => api.setTrip(actions.session, player.id, trip))) {
      onDone();
    }
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <p className="muted">
        Из офиса «{actions.officeName(player.office_id)}». До конца последнего дня сотрудник отмечается на экране выбранного
        офиса, получает задания с его коллегами и подчиняется его ограничениям. Розыгрыш парковки и статистика остаются в
        домашнем офисе.
      </p>
      <label>
        Офис командировки
        <OfficeSelect
          actions={actions}
          value={officeId}
          except={player.office_id}
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
      <label>
        Последний день
        <input type="date" min={today()} value={until} onChange={(e) => setUntil(e.target.value)} required />
      </label>
      <div className="form-actions">
        <button type="submit" disabled={!officeId || !departmentId || !until}>
          {player.trip ? "Сохранить" : "Отправить в командировку"}
        </button>
        <button type="button" className="secondary" onClick={onDone}>
          Отмена
        </button>
      </div>
    </form>
  );
}
