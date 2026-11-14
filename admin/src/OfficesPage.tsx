import { useMemo, useState, type FormEvent } from "react";
import { api, type Office, type OfficeFields } from "./api";
import type { DashboardActions } from "./actions";
import { useDialogs } from "./Dialogs";
import { FilterBar, matches, useFilters } from "./FilterBar";
import { Icon } from "./Icon";
import { href, navigate } from "./router";
import { Drawer, EmptyState, PageHeader } from "./ui";

const EMPTY: OfficeFields = { name: "", city: "", networks: [], timezone: "" };
const DEFAULT_FILTERS = { q: "", city: "", network: "" };

/** Time zones of Russian cities first; any other IANA zone of the browser list can be typed. */
const RUSSIAN_ZONES = [
  "Europe/Kaliningrad",
  "Europe/Moscow",
  "Europe/Samara",
  "Asia/Yekaterinburg",
  "Asia/Omsk",
  "Asia/Novosibirsk",
  "Asia/Krasnoyarsk",
  "Asia/Irkutsk",
  "Asia/Yakutsk",
  "Asia/Vladivostok",
  "Asia/Magadan",
  "Asia/Kamchatka",
];

function knownZones(): string[] {
  const intl = Intl as unknown as { supportedValuesOf?: (key: string) => string[] };
  const all = intl.supportedValuesOf?.("timeZone") ?? [];
  return [...RUSSIAN_ZONES, ...all.filter((zone) => !RUSSIAN_ZONES.includes(zone))];
}

/** "UTC+5" for the zone right now; "" for a zone the browser does not know. */
export function zoneOffsetLabel(zone: string): string {
  try {
    const part = new Intl.DateTimeFormat("en-US", { timeZone: zone, timeZoneName: "shortOffset" })
      .formatToParts(new Date())
      .find((item) => item.type === "timeZoneName");
    return part ? part.value.replace("GMT", "UTC").replace(/^UTC$/, "UTC+0") : "";
  } catch {
    return "";
  }
}

/** "203.0.113.0/24, 198.51.100.7" or one per line -> the list the server checks. */
function parseNetworks(text: string): string[] {
  return text
    .split(/[\s,;]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

/** Players of an office today: its own (not away on a trip), the visitors on a trip and on site now. */
export function officeCounts(actions: DashboardActions, office: Office) {
  const players = actions.players ?? [];
  return {
    home: players.filter((p) => p.office_id === office.id && !p.trip).length,
    visitors: players.filter((p) => p.trip?.office_id === office.id).length,
    away: players.filter((p) => p.office_id === office.id && p.trip).length,
    onSite: players.filter((p) => p.on_site && p.current_office_id === office.id).length,
  };
}

/**
 * Offices are the game zones: a player meets colleagues only in the office they are in today. Each
 * office has its own Wi-Fi network, office screen with the entry codes, limits and parking draw.
 */
export function OfficesPage({ actions, creating }: { actions: DashboardActions; creating: boolean }) {
  const { offices } = actions;
  const { values, set, reset, active } = useFilters("offices", DEFAULT_FILTERS);
  const cities = [...new Set(offices.map((o) => o.city).filter(Boolean))].sort((a, b) => a.localeCompare(b, "ru"));
  const close = () => navigate(href(["offices"]));

  const visible = useMemo(
    () =>
      offices
        .filter((o) => !values.city || o.city === values.city)
        .filter((o) => !values.network || (values.network === "set") === o.networks.length > 0)
        .filter((o) => matches(values.q, o.name, o.city, o.timezone, o.networks.join(" "), o.id)),
    [offices, values],
  );

  return (
    <>
      <PageHeader
        title="Офисы"
        actions={
          <button type="button" onClick={() => navigate(href(["offices"], { new: "1" }))}>
            <Icon name="plus" size={16} /> Новый офис
          </button>
        }
      />
      <section className="card flush">
        <FilterBar
          query={values.q}
          onQuery={(text) => set("q", text)}
          placeholder="Название, город, сеть или код экрана"
          filters={[
            ...(cities.length > 1 ? [{ key: "city", label: "Город", allLabel: "все", options: cities.map((c) => ({ value: c, label: c })) }] : []),
            {
              key: "network",
              label: "Сеть Wi-Fi",
              allLabel: "любая",
              options: [
                { value: "set", label: "задана" },
                { value: "none", label: "не задана" },
              ],
            },
          ]}
          values={values}
          onChange={(key, value) => set(key as keyof typeof DEFAULT_FILTERS, value)}
          onReset={reset}
          active={active}
          shown={visible.length}
          total={offices.length}
          noun={["офис", "офиса", "офисов"]}
        />
        {visible.length === 0 ? (
          <EmptyState icon="building" title="Офисов не найдено">
            <button type="button" className="link" onClick={reset}>
              Сбросить фильтры
            </button>
          </EmptyState>
        ) : (
          <div className="table-wrap">
            <table className="data-table">
              <thead>
                <tr>
                  <th>Офис</th>
                  <th>Часовой пояс</th>
                  <th>Сеть Wi-Fi</th>
                  <th className="num">Сотрудников</th>
                  <th className="num">Сейчас в офисе</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((office) => {
                  const counts = officeCounts(actions, office);
                  const to = href(["offices", office.id]);
                  return (
                    <tr key={office.id} className="clickable" onClick={() => navigate(to)}>
                      <td>
                        <a className="row-link" href={to} onClick={(e) => e.stopPropagation()}>
                          <span className="avatar small square" aria-hidden="true">
                            <Icon name="building" size={14} />
                          </span>
                          <span>
                            <span className="player-name">{office.name}</span>
                            <span className="muted">{office.city || "город не указан"}</span>
                          </span>
                        </a>
                      </td>
                      <td className="nowrap">
                        {office.timezone ? (
                          <>
                            {office.timezone} <span className="muted">{zoneOffsetLabel(office.timezone)}</span>
                          </>
                        ) : (
                          <span className="muted">по умолчанию</span>
                        )}
                      </td>
                      <td>
                        {office.networks.length ? (
                          <span className="badge present">
                            {office.networks.length} {office.networks.length === 1 ? "сеть" : "сети"}
                          </span>
                        ) : (
                          <span className="badge missed">не задана</span>
                        )}
                      </td>
                      <td className="num nowrap">
                        {counts.home}
                        {counts.visitors > 0 && <span className="muted"> +{counts.visitors}</span>}
                      </td>
                      <td className="num">{counts.onSite}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>
      {creating && (
        <Drawer title="Новый офис" onClose={close}>
          <OfficeForm actions={actions} office={null} onDone={close} />
        </Drawer>
      )}
    </>
  );
}

/** New office (office = null) or the settings of one. */
export function OfficeForm({ actions, office, onDone }: { actions: DashboardActions; office: Office | null; onDone?: () => void }) {
  const { session, run } = actions;
  const { notify } = useDialogs();
  const initial = office ? { name: office.name, city: office.city, networks: office.networks, timezone: office.timezone ?? "" } : EMPTY;
  const [form, setForm] = useState<OfficeFields>(initial);
  const [networks, setNetworks] = useState(office ? office.networks.join("\n") : "");
  const [zones] = useState(knownZones);
  const changed =
    JSON.stringify({ ...form, networks: parseNetworks(networks) }) !== JSON.stringify({ ...initial, networks: initial.networks });

  async function submit(event: FormEvent) {
    event.preventDefault();
    const fields = { ...form, networks: parseNetworks(networks), timezone: form.timezone.trim() };
    const ok = await run(() => (office ? api.updateOffice(session, office.id, fields) : api.createOffice(session, fields)));
    if (ok) {
      notify(office ? "Настройки офиса сохранены." : `Офис «${fields.name}» создан.`);
      onDone?.();
    }
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <label>
        Название
        <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} maxLength={60} required />
      </label>
      <label>
        Город
        <input value={form.city} onChange={(e) => setForm({ ...form, city: e.target.value })} maxLength={60} />
      </label>
      <label>
        Часовой пояс
        <input
          list="office-zones"
          placeholder="Asia/Yekaterinburg"
          value={form.timezone}
          onChange={(e) => setForm({ ...form, timezone: e.target.value })}
          maxLength={64}
        />
        <datalist id="office-zones">
          {zones.map((zone) => (
            <option key={zone} value={zone}>
              {zoneOffsetLabel(zone)}
            </option>
          ))}
        </datalist>
        <span className="hint">
          По нему считаются дни, серии, штрафы, часы заданий и розыгрыш парковки игроков офиса. Пусто — пояс по умолчанию из
          правил сервера.
          {form.timezone.trim() && ` Сейчас: ${zoneOffsetLabel(form.timezone.trim()) || "пояс не найден"}.`}
        </span>
      </label>
      <label>
        Сеть Wi-Fi офиса
        <textarea rows={3} placeholder={"203.0.113.0/24\n198.51.100.7"} value={networks} onChange={(e) => setNetworks(e.target.value)} />
        <span className="hint">Внешние адреса или CIDR-префиксы, по одному в строке. Пусто — сеть не проверяется.</span>
      </label>
      <div className="form-actions">
        <button type="submit" disabled={!form.name.trim() || (office !== null && !changed)}>
          {office ? "Сохранить" : "Добавить офис"}
        </button>
        {onDone && (
          <button type="button" className="secondary" onClick={onDone}>
            Отмена
          </button>
        )}
      </div>
    </form>
  );
}
