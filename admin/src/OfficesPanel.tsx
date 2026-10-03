import { useState, type FormEvent } from "react";
import { api, type Office, type OfficeFields, type User } from "./api";
import type { DashboardActions } from "./Dashboard";

const EMPTY: OfficeFields = { name: "", city: "", networks: [] };

/** "203.0.113.0/24, 198.51.100.7" or one per line -> the list the server checks. */
function parseNetworks(text: string): string[] {
  return text
    .split(/[\s,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

/**
 * Offices are the game zones: a player meets colleagues only in the office they are in today. Each
 * office has its own Wi-Fi network, office screen with the entry codes, limits and parking draw.
 */
export function OfficesPanel({ actions, players }: { actions: DashboardActions; players: User[] }) {
  const { session, offices, run } = actions;
  const [editing, setEditing] = useState<Office | null>(null);
  const [form, setForm] = useState<OfficeFields>(EMPTY);
  const [networks, setNetworks] = useState("");

  function edit(office: Office | null) {
    setEditing(office);
    setForm(office ? { name: office.name, city: office.city, networks: office.networks } : EMPTY);
    setNetworks(office ? office.networks.join("\n") : "");
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const fields = { ...form, networks: parseNetworks(networks) };
    const ok = await run(() => (editing ? api.updateOffice(session, editing.id, fields) : api.createOffice(session, fields)));
    if (ok) {
      edit(null);
    }
  }

  const homePlayers = (office: Office) => players.filter((user) => user.office_id === office.id && !user.trip).length;
  const visitors = (office: Office) => players.filter((user) => user.trip?.office_id === office.id).length;
  const away = (office: Office) => players.filter((user) => user.office_id === office.id && user.trip).length;

  return (
    <section className="card">
      <h2>Офисы</h2>
      <p className="muted">
        Офис — игровая зона. Совместные задания (селфи, кофе вслепую, бинго) назначают и засчитывают только коллег из
        того офиса, где игрок сегодня. У каждого офиса своя сеть Wi-Fi, свой экран с QR-кодами входа и выхода, свои
        ограничения и свой розыгрыш парковки.
      </p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Офис</th>
              <th>Сеть офиса</th>
              <th className="num">Игроков</th>
              <th>Код для экрана</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {offices.map((office) => (
              <tr key={office.id}>
                <td>
                  <div className="player-name">{office.name}</div>
                  <span className="muted">{office.city || "город не указан"}</span>
                </td>
                <td>
                  {office.networks.length ? (
                    office.networks.map((network) => (
                      <code key={network} className="network">
                        {network}
                      </code>
                    ))
                  ) : (
                    <span className="hint error">не задана — сеть не проверяется</span>
                  )}
                </td>
                <td className="num nowrap">
                  {homePlayers(office)}
                  {visitors(office) > 0 && <span className="muted"> + {visitors(office)} в командировке</span>}
                  {away(office) > 0 && <div className="hint">в командировке в других офисах: {away(office)}</div>}
                </td>
                <td>
                  <code>{office.id}</code>
                </td>
                <td className="actions">
                  <button className="secondary" onClick={() => edit(office)}>
                    Изменить
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h3>{editing ? `Изменить офис «${editing.name}»` : "Новый офис"}</h3>
      <form className="grid-form limits-form" onSubmit={submit}>
        <label>
          Название
          <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} maxLength={60} required />
        </label>
        <label>
          Город
          <input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} maxLength={60} />
        </label>
        <label>
          Сеть Wi-Fi офиса
          <textarea
            rows={3}
            placeholder={"203.0.113.0/24\n198.51.100.7"}
            value={networks}
            onChange={(e) => setNetworks(e.target.value)}
          />
          <span className="hint">Внешние адреса или CIDR-префиксы, по одному в строке. Пусто — сеть не проверяется.</span>
        </label>
        <div className="form-actions">
          <button type="submit" disabled={!form.name.trim()}>
            {editing ? "Сохранить" : "Добавить офис"}
          </button>
          {editing && (
            <button type="button" className="secondary" onClick={() => edit(null)}>
              Отмена
            </button>
          )}
        </div>
      </form>
    </section>
  );
}
