import { useCallback, useEffect, useState } from "react";
import { api, type GraffitiWall, type Office } from "./api";
import type { DashboardActions } from "./actions";
import { ChatModeration } from "./ChatModeration";
import { CreateDepartmentForm, DepartmentsTable } from "./DepartmentsPage";
import { useDialogs } from "./Dialogs";
import { Icon } from "./Icon";
import { LimitsPanel } from "./LimitsPanel";
import { OfficeForm, officeCounts, zoneOffsetLabel } from "./OfficesPage";
import { href } from "./router";
import { Drawer, EmptyState, Loading, PageHeader, StatCard, TabLinks } from "./ui";

export type OfficeTab = "settings" | "departments" | "limits" | "chat" | "graffiti";

export const OFFICE_TABS: { id: OfficeTab; label: string; icon: "settings" | "layers" | "sliders" | "chat" | "image" }[] = [
  { id: "settings", label: "Настройки", icon: "settings" },
  { id: "departments", label: "Департаменты", icon: "layers" },
  { id: "limits", label: "Ограничения", icon: "sliders" },
  { id: "chat", label: "Чат", icon: "chat" },
  { id: "graffiti", label: "Граффити", icon: "image" },
];

/** One office: its numbers on top and its settings, departments, limits, chat and graffiti wall in tabs. */
export function OfficePage({ actions, officeId, tab }: { actions: DashboardActions; officeId: string; tab: string }) {
  const office = actions.offices.find((o) => o.id === officeId);
  const current: OfficeTab = OFFICE_TABS.some((t) => t.id === tab) ? (tab as OfficeTab) : "settings";
  const crumbs = [{ label: "Офисы", href: href(["offices"]) }];

  if (actions.offices.length === 0) {
    return <Loading />;
  }
  if (!office) {
    return (
      <>
        <PageHeader title="Офис не найден" crumbs={crumbs} />
        <EmptyState icon="building" title="Такого офиса нет">
          <a href={href(["offices"])}>Все офисы</a>
        </EmptyState>
      </>
    );
  }

  const counts = officeCounts(actions, office);
  const playersHref = (query: Record<string, string>) => href(["players"], { office: office.id, ...query });

  return (
    <>
      <PageHeader
        crumbs={crumbs}
        title={office.name}
        description={
          <>
            {office.city || "Город не указан"} · {office.timezone ? `${office.timezone} ${zoneOffsetLabel(office.timezone)}` : "пояс по умолчанию"} · код
            экрана <code>{office.id}</code>
          </>
        }
      >
        {office.networks.length === 0 && (
          <div className="notice warn">
            <span>
              <Icon name="alert" size={16} /> Сеть Wi-Fi не задана: присутствие в этом офисе не проверяется по сети.
            </span>
          </div>
        )}
      </PageHeader>
      <div className="stat-grid">
        <StatCard label="Сотрудников" value={counts.home} hint={counts.away ? `ещё ${counts.away} в командировке` : undefined} href={playersHref({})} />
        <StatCard label="Сейчас в офисе" value={counts.onSite} tone="good" href={playersHref({ presence: "on_site" })} />
        <StatCard label="В командировке здесь" value={counts.visitors} />
        <StatCard label="Департаментов" value={actions.departments.filter((d) => d.office_id === office.id).length} href={href(["offices", office.id], { tab: "departments" })} />
      </div>
      <TabLinks
        current={current}
        tabs={OFFICE_TABS.map((t) => ({ id: t.id, label: t.label, icon: t.icon, href: href(["offices", office.id], t.id === "settings" ? {} : { tab: t.id }) }))}
      />
      {current === "settings" && (
        <section className="card narrow-card">
          <OfficeForm key={office.id} actions={actions} office={office} />
        </section>
      )}
      {current === "departments" && <OfficeDepartments actions={actions} office={office} />}
      {current === "limits" && <LimitsPanel key={office.id} actions={actions} officeId={office.id} />}
      {current === "chat" && <ChatModeration key={office.id} actions={actions} office={office} />}
      {current === "graffiti" && <GraffitiTab key={office.id} actions={actions} office={office} />}
    </>
  );
}

function OfficeDepartments({ actions, office }: { actions: DashboardActions; office: Office }) {
  const [creating, setCreating] = useState(false);
  return (
    <section className="card flush">
      <div className="card-head">
        <h2>Департаменты офиса</h2>
        {actions.createDepartment && (
          <button type="button" className="secondary" onClick={() => setCreating(true)}>
            <Icon name="plus" size={16} /> Добавить
          </button>
        )}
      </div>
      <DepartmentsTable actions={actions} departments={actions.departments.filter((d) => d.office_id === office.id)} showOffice={false} />
      {creating && (
        <Drawer title="Новый департамент" onClose={() => setCreating(false)}>
          <CreateDepartmentForm actions={actions} officeId={office.id} onDone={() => setCreating(false)} />
        </Drawer>
      )}
    </section>
  );
}

function GraffitiTab({ actions, office }: { actions: DashboardActions; office: Office }) {
  const { session, run, report } = actions;
  const { confirm, notify } = useDialogs();
  const [wall, setWall] = useState<GraffitiWall | null>(null);

  const load = useCallback(async () => {
    try {
      setWall(await api.getGraffiti(session, office.id));
    } catch (e) {
      report(e);
    }
  }, [session, office.id, report]);

  useEffect(() => {
    void load();
  }, [load]);

  async function clear() {
    const ok = await confirm({
      title: "Очистить стену?",
      text: `Все рисунки на стене офиса «${office.name}» пропадут у всех игроков.`,
      confirmLabel: "Очистить",
      danger: true,
    });
    if (ok && (await run(() => api.clearGraffiti(session, office.id)))) {
      notify("Стена очищена.");
      await load();
    }
  }

  const playerName = (id: string) => actions.players?.find((p) => p.id === id)?.display_name || id;

  return (
    <section className="card">
      <div className="card-head">
        <div>
          <h2>Стена граффити</h2>
        </div>
        <button type="button" className="danger" disabled={!wall?.png} onClick={() => void clear()}>
          <Icon name="trash" size={16} /> Очистить стену
        </button>
      </div>
      {wall === null ? (
        <Loading />
      ) : wall.png ? (
        <>
          <img className="graffiti-wall" src={`data:image/png;base64,${wall.png}`} alt={`Граффити офиса ${office.name}`} />
          {wall.authors.length > 0 && (
            <p className="hint">
              Рисунков: {wall.tags}. Последние авторы:{" "}
              {[...new Set(wall.authors.slice(-10).reverse().map((author) => playerName(author.user_id)))].join(", ")}
            </p>
          )}
        </>
      ) : (
        <EmptyState icon="image" title="Стена чистая" />
      )}
    </section>
  );
}
