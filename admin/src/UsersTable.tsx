import { useState } from "react";
import { api, type User } from "./api";
import type { DashboardActions } from "./Dashboard";
import { DepartmentSelect } from "./DepartmentSelect";
import { formatDateTime } from "./format";
import { generatePassword } from "./password";
import { TripForm, tripLabel } from "./TripForm";
import { OfficeSelect } from "./OfficeSelect";

export function UsersTable({ actions, users }: { actions: DashboardActions; users: User[] }) {
  const { session, run } = actions;
  const [tripUser, setTripUser] = useState<User | null>(null);

  async function resetPassword(user: User) {
    const password = window.prompt(`Новый пароль для ${user.username} (от 8 символов):`, generatePassword());
    if (password && (await run(() => api.setPassword(session, user.id, password)))) {
      window.alert(`Пароль изменён.\nлогин: ${user.username}\nпароль: ${password}\nСтарые сессии завершены.`);
    }
  }

  function toggleBan(user: User) {
    const question = user.banned ? `Вернуть доступ ${user.username}?` : `Заблокировать ${user.username}? Сессии завершатся сразу.`;
    if (window.confirm(question)) {
      void run(() => api.setBanned(session, user.id, !user.banned));
    }
  }

  function endTrip(user: User) {
    if (window.confirm(`Завершить командировку ${user.display_name}? С этого момента игрок снова в своём офисе.`)) {
      void run(() => api.setTrip(session, user.id, { office_id: "", department_id: "", until: "" }));
    }
  }

  return (
    <section className="card">
      <h2>Игроки ({users.length})</h2>
      {tripUser && <TripForm actions={actions} user={tripUser} onDone={() => setTripUser(null)} />}
      {users.length === 0 ? (
        <p className="muted">Пока никого. Создайте первый аккаунт выше.</p>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Игрок</th>
                <th>Офис и департамент</th>
                <th>Командировка</th>
                <th>Создан</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {users.map((user) => (
                <UserRow
                  key={user.id}
                  actions={actions}
                  user={user}
                  onTrip={() => setTripUser(user)}
                  onEndTrip={() => endTrip(user)}
                  onPassword={() => void resetPassword(user)}
                  onBan={() => toggleBan(user)}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function UserRow({
  actions,
  user,
  onTrip,
  onEndTrip,
  onPassword,
  onBan,
}: {
  actions: DashboardActions;
  user: User;
  onTrip: () => void;
  onEndTrip: () => void;
  onPassword: () => void;
  onBan: () => void;
}) {
  const { session, run } = actions;
  // A new home office waits for a department of that office before it is saved.
  const [office, setOffice] = useState(user.office_id);
  const moving = office !== user.office_id;

  function changeDepartment(id: string) {
    const changes = moving ? { office_id: office, department_id: id } : { department_id: id };
    void run(() => api.updateUser(session, user.id, changes));
  }

  return (
    <tr className={user.banned ? "banned" : ""}>
      <td className="nowrap">
        <div className="player-name">{user.display_name}</div>
        <code className="muted">{user.username}</code>
        {user.banned && <div className="hint">заблокирован</div>}
      </td>
      <td>
        <div className="placement">
          <OfficeSelect actions={actions} value={office} onChange={setOffice} compact />
          <DepartmentSelect actions={actions} officeId={office} value={moving ? "" : user.department_id} onChange={changeDepartment} />
        </div>
        {moving && (
          <div className="hint">
            Выберите департамент нового офиса ·{" "}
            <button className="link" onClick={() => setOffice(user.office_id)}>
              отмена
            </button>
          </div>
        )}
      </td>
      <td>
        {user.trip ? (
          <div className="trip">
            <span className="trip-label">{tripLabel(actions, user.trip)}</span>
            <button className="link" onClick={onEndTrip}>
              завершить
            </button>
          </div>
        ) : (
          <span className="muted">—</span>
        )}
      </td>
      <td className="nowrap">{formatDateTime(user.created_at)}</td>
      <td className="actions">
        <div className="row-actions">
          <button className="secondary" onClick={onTrip} disabled={actions.offices.length < 2}>
            Командировка
          </button>
          <button className="secondary" onClick={onPassword}>
            Пароль
          </button>
          <button className={user.banned ? "secondary" : "danger"} onClick={onBan}>
            {user.banned ? "Разблокировать" : "Заблокировать"}
          </button>
        </div>
      </td>
    </tr>
  );
}
