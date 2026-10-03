import { useState, type FormEvent } from "react";
import { api, type Trip, type User } from "./api";
import type { DashboardActions } from "./Dashboard";
import { DepartmentSelect } from "./DepartmentSelect";
import { OfficeSelect } from "./OfficeSelect";

/** "Москва · Дизайн, до 16.10" */
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
export function TripForm({ actions, user, onDone }: { actions: DashboardActions; user: User; onDone: () => void }) {
  const [officeId, setOfficeId] = useState(user.trip?.office_id ?? "");
  const [departmentId, setDepartmentId] = useState(user.trip?.department_id ?? "");
  const [until, setUntil] = useState(user.trip?.until ?? "");

  async function submit(event: FormEvent) {
    event.preventDefault();
    const trip = { office_id: officeId, department_id: departmentId, until };
    if (await actions.run(() => api.setTrip(actions.session, user.id, trip))) {
      onDone();
    }
  }

  return (
    <form className="trip-form" onSubmit={submit}>
      <h3>
        Командировка: {user.display_name}
        <span className="muted"> · из офиса «{actions.officeName(user.office_id)}»</span>
      </h3>
      <div className="grid-form">
        <label>
          Офис
          <OfficeSelect
            actions={actions}
            value={officeId}
            except={user.office_id}
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
            {user.trip ? "Сохранить" : "Отправить"}
          </button>
          <button type="button" className="secondary" onClick={onDone}>
            Отмена
          </button>
        </div>
      </div>
      <p className="hint">
        До конца последнего дня игрок отмечается на экране этого офиса, получает задания с его коллегами и подчиняется
        его ограничениям. Розыгрыш парковки и статистика остаются в домашнем офисе.
      </p>
    </form>
  );
}
