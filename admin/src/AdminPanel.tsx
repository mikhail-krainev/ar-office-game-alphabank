import { useCallback, useEffect, useMemo, useState } from "react";
import type { Session } from "@heroiclabs/nakama-js";
import { api, type Clock, type Department, type Manager, type Office, type PlayerSummary, type RewardsOverview } from "./api";
import type { DashboardActions } from "./actions";
import { ClockPanel } from "./ClockPanel";
import type { ListSearch } from "./CommandPalette";
import { ConsolePanel } from "./ConsolePanel";
import { CreateUserForm } from "./CreateUserForm";
import { DepartmentsPage } from "./DepartmentsPage";
import { useDialogs } from "./Dialogs";
import { Icon } from "./Icon";
import { label, RARITY_LABELS } from "./labels";
import { ManagersPage } from "./ManagersPage";
import { errorText, isSessionError } from "./messages";
import { OFFICE_TABS, OfficePage } from "./OfficePage";
import { OfficesPage } from "./OfficesPage";
import { OverviewPage, type Attention } from "./OverviewPage";
import { PlayerPage } from "./PlayerPage";
import { PlayersPage } from "./PlayersPage";
import { RewardsPanel } from "./RewardsPanel";
import { href, navigate, useRoute, type Route } from "./router";
import { scopeLabel } from "./ScopeEditor";
import type { SearchItem } from "./search";
import { Shell, type NavGroup } from "./Shell";
import { Drawer } from "./ui";

interface AdminData {
  offices: Office[];
  departments: Department[];
  players: PlayerSummary[] | null;
  managers: Manager[] | null;
  rewards: RewardsOverview | null;
  clock: Clock | null;
}

const EMPTY_DATA: AdminData = { offices: [], departments: [], players: null, managers: null, rewards: null, clock: null };

const LISTS: ListSearch[] = [
  { label: "среди сотрудников", href: (q) => href(["players"], { q }) },
  { label: "среди руководителей", href: (q) => href(["managers"], { q }) },
];

/** The main admin's panel: everything of every office; the server checks the role of every call. */
export function AdminPanel({ session, onSessionLost }: { session: Session; onSessionLost: () => void }) {
  const { notify } = useDialogs();
  const [data, setData] = useState<AdminData>(EMPTY_DATA);
  const route = useRoute();

  const fail = useCallback(
    (e: unknown) => {
      if (isSessionError(e)) {
        onSessionLost();
      } else {
        notify(errorText(e), "error");
      }
    },
    [onSessionLost, notify],
  );

  const reload = useCallback(async () => {
    try {
      const [offices, departments, players, managers, rewards, clock] = await Promise.all([
        api.listOffices(session),
        api.listDepartments(session),
        api.statsOverview(session),
        api.listManagers(session),
        api.getRewards(session),
        api.getClock(session),
      ]);
      setData({ offices, departments, players, managers, rewards, clock });
    } catch (e) {
      fail(e);
    }
  }, [session, fail]);

  useEffect(() => {
    void reload();
  }, [reload]);

  const run = useCallback(
    async (action: () => Promise<unknown>) => {
      try {
        await action();
        await reload();
        return true;
      } catch (e) {
        fail(e);
        return false;
      }
    },
    [reload, fail],
  );

  const createDepartment = useCallback(
    async (name: string, officeId: string) => {
      let created: Department | null = null;
      await run(async () => {
        created = await api.createDepartment(session, name, officeId);
      });
      return created;
    },
    [run, session],
  );

  const { offices, departments } = data;
  const officeName = useCallback((id: string) => offices.find((o) => o.id === id)?.name ?? "—", [offices]);
  const departmentName = useCallback((id: string) => departments.find((d) => d.id === id)?.name ?? "—", [departments]);
  const loadPlayerStats = useCallback((userId: string) => api.playerStats(session, userId), [session]);

  const actions: DashboardActions = {
    session,
    role: "admin",
    offices,
    departments,
    players: data.players,
    officeName,
    departmentName,
    run,
    reload,
    createDepartment,
    loadPlayerStats,
    report: fail,
  };

  const outOfStock = data.rewards?.items.filter((item) => item.left === 0).length ?? 0;
  const nav: NavGroup[] = [
    { title: "Главное", items: [{ id: "overview", label: "Обзор", icon: "home", href: "#/" }] },
    {
      title: "Люди",
      items: [
        { id: "players", label: "Сотрудники", icon: "users", href: href(["players"]) },
        { id: "managers", label: "Руководители", icon: "shield", href: href(["managers"]) },
      ],
    },
    {
      title: "Структура",
      items: [
        { id: "offices", label: "Офисы", icon: "building", href: href(["offices"]) },
        { id: "departments", label: "Департаменты", icon: "layers", href: href(["departments"]) },
      ],
    },
    { title: "Игра", items: [{ id: "rewards", label: "Награды", icon: "gift", href: href(["rewards"]), badge: outOfStock }] },
    {
      title: "Система",
      items: [
        ...(data.clock?.enabled ? [{ id: "clock", label: "Тестовое время", icon: "clock" as const, href: href(["clock"]) }] : []),
        { id: "console", label: "Консоль", icon: "terminal", href: href(["console"]) },
      ],
    },
  ];

  const search = useSearchIndex(data, officeName, departmentName, nav);
  const section = route.parts[0] ?? "overview";

  return (
    <Shell
      panelLabel="Администратор"
      accountName={session.username ?? "admin"}
      accountRole="Главный администратор"
      nav={nav}
      current={section}
      search={search}
      lists={LISTS}
      onSignOut={onSessionLost}
    >
      <AdminRoute route={route} actions={actions} data={data} onClockChange={(clock) => setData((d) => ({ ...d, clock }))} />
    </Shell>
  );
}

function AdminRoute({
  route,
  actions,
  data,
  onClockChange,
}: {
  route: Route;
  actions: DashboardActions;
  data: AdminData;
  onClockChange: (clock: Clock) => void;
}) {
  const [section = "overview", id = ""] = route.parts;
  const creating = route.query.get("new") === "1";

  switch (section) {
    case "players":
      if (id) {
        return <PlayerPage key={id} actions={actions} userId={id} base="players" listLabel="Сотрудники" canDelete />;
      }
      return (
        <>
          <PlayersPage
            actions={actions}
            base="players"
            title="Сотрудники"
            onCreate={() => navigate(href(["players"], { new: "1" }))}
            headerActions={
              <button type="button" onClick={() => navigate(href(["players"], { new: "1" }))}>
                <Icon name="plus" size={16} /> Добавить сотрудника
              </button>
            }
          />
          {creating && (
            <Drawer title="Новый сотрудник" onClose={() => navigate(href(["players"]))}>
              <CreateUserForm actions={actions} create={(user) => api.createUser(actions.session, user)} onClose={() => navigate(href(["players"]))} />
            </Drawer>
          )}
        </>
      );
    case "managers":
      return <ManagersPage actions={actions} managers={data.managers} selectedId={id} creating={creating} onChanged={actions.reload} />;
    case "offices":
      return id ? <OfficePage actions={actions} officeId={id} tab={route.query.get("tab") ?? ""} /> : <OfficesPage actions={actions} creating={creating} />;
    case "departments":
      return <DepartmentsPage actions={actions} creating={creating} />;
    case "rewards":
      return <RewardsPanel actions={actions} />;
    case "clock":
      return data.clock?.enabled ? <ClockPanel actions={actions} clock={data.clock} onChange={onClockChange} /> : null;
    case "console":
      return <ConsolePanel actions={actions} />;
    default:
      return (
        <OverviewPage
          actions={actions}
          title="Обзор"
          base="players"
          groupBy="office"
          attention={adminAttention(data)}
        />
      );
  }
}

function adminAttention(data: AdminData): Attention[] {
  const items: Attention[] = data.offices
    .filter((office) => office.networks.length === 0)
    .map((office) => ({
      id: `net:${office.id}`,
      icon: "wifi",
      text: <>Офис «{office.name}»: не задана сеть Wi-Fi</>,
      href: href(["offices", office.id]),
    }));
  const out = data.rewards?.items.filter((item) => item.left === 0) ?? [];
  if (out.length > 0) {
    items.push({ id: "stock", icon: "gift", text: <>Нет в наличии наград: {out.length}</>, href: href(["rewards"], { stock: "out" }) });
  }
  const emptyOffices = data.offices.filter((office) => !data.departments.some((d) => d.office_id === office.id));
  for (const office of emptyOffices) {
    items.push({ id: `dep:${office.id}`, icon: "layers", text: <>Офис «{office.name}»: нет департаментов</>, href: href(["offices", office.id], { tab: "departments" }) });
  }
  return items;
}

/** Everything the global search of the admin finds. */
function useSearchIndex(
  data: AdminData,
  officeName: (id: string) => string,
  departmentName: (id: string) => string,
  nav: NavGroup[],
): SearchItem[] {
  return useMemo(() => {
    const pages: SearchItem[] = nav.flatMap((group) =>
      group.items.map((item) => ({ id: `page:${item.id}`, group: "Разделы" as const, title: item.label, subtitle: group.title, href: item.href, icon: item.icon })),
    );
    const officeTabs: SearchItem[] = data.offices.flatMap((office) =>
      OFFICE_TABS.filter((tab) => tab.id !== "settings").map((tab) => ({
        id: `tab:${office.id}:${tab.id}`,
        group: "Разделы" as const,
        title: `${tab.label} · ${office.name}`,
        subtitle: "Офис",
        keywords: tab.id === "limits" ? "лимиты пауза отдых время в игре часы заданий" : tab.id === "chat" ? "модерация сообщения" : "",
        href: href(["offices", office.id], { tab: tab.id }),
        icon: tab.icon,
      })),
    );
    const actionItems: SearchItem[] = [
      { id: "new:player", group: "Действия", title: "Добавить сотрудника", keywords: "создать аккаунт выдать доступ", href: href(["players"], { new: "1" }), icon: "plus" },
      { id: "new:manager", group: "Действия", title: "Назначить руководителя", keywords: "создать руководитель", href: href(["managers"], { new: "1" }), icon: "plus" },
      { id: "new:office", group: "Действия", title: "Новый офис", keywords: "создать добавить офис", href: href(["offices"], { new: "1" }), icon: "plus" },
      { id: "new:department", group: "Действия", title: "Новый департамент", keywords: "создать добавить отдел", href: href(["departments"], { new: "1" }), icon: "plus" },
    ];
    const players: SearchItem[] = (data.players ?? []).map((p) => ({
      id: `player:${p.id}`,
      group: "Сотрудники",
      title: p.display_name || p.username,
      subtitle: `${p.username} · ${officeName(p.office_id)} · ${departmentName(p.department_id)}`,
      keywords: `${p.status} ${p.banned ? "заблокирован" : ""}`,
      href: href(["players", p.id]),
      icon: "user",
    }));
    const managers: SearchItem[] = (data.managers ?? []).map((m) => ({
      id: `manager:${m.id}`,
      group: "Руководители",
      title: m.display_name || m.username,
      subtitle: `${m.username} · ${scopeLabel(m.scope, data.offices, data.departments)}`,
      href: href(["managers", m.id]),
      icon: "shield",
    }));
    const offices: SearchItem[] = data.offices.map((o) => ({
      id: `office:${o.id}`,
      group: "Офисы",
      title: o.name,
      subtitle: o.city || "город не указан",
      keywords: `${o.id} ${o.timezone} ${o.networks.join(" ")}`,
      href: href(["offices", o.id]),
      icon: "building",
    }));
    const departments: SearchItem[] = data.departments.map((d) => ({
      id: `department:${d.id}`,
      group: "Департаменты",
      title: d.name,
      subtitle: `Офис «${officeName(d.office_id)}»`,
      keywords: "отдел",
      href: href(["players"], { office: d.office_id, department: d.id }),
      icon: "layers",
    }));
    const rewards: SearchItem[] = (data.rewards?.items ?? []).map((item) => ({
      id: `reward:${item.id}`,
      group: "Награды",
      title: item.name,
      subtitle: `${label(RARITY_LABELS, item.rarity)} · ${item.price} монет${item.left === 0 ? " · нет в наличии" : ""}`,
      keywords: item.cosmetic ? "гардероб" : "",
      href: href(["rewards"], { q: item.name }),
      icon: "gift",
    }));
    return [...players, ...managers, ...offices, ...departments, ...rewards, ...pages, ...officeTabs, ...actionItems];
  }, [data, officeName, departmentName, nav]);
}
