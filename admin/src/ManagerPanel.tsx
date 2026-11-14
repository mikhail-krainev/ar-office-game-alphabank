import { useCallback, useEffect, useMemo, useState } from "react";
import type { Session } from "@heroiclabs/nakama-js";
import { ApiError, managerApi, type ManagerProfile, type PlayerSummary } from "./api";
import type { DashboardActions } from "./actions";
import type { ListSearch } from "./CommandPalette";
import { CreateUserForm } from "./CreateUserForm";
import { useDialogs } from "./Dialogs";
import { Icon } from "./Icon";
import { errorText, isSessionError } from "./messages";
import { OverviewPage } from "./OverviewPage";
import { PlayerPage } from "./PlayerPage";
import { PlayersPage } from "./PlayersPage";
import { href, navigate, useRoute } from "./router";
import { scopeLabel } from "./ScopeEditor";
import type { SearchItem } from "./search";
import { Shell, type NavGroup } from "./Shell";
import { Drawer, Loading, PageHeader } from "./ui";

const LISTS: ListSearch[] = [{ label: "среди сотрудников", href: (q) => href(["staff"], { q }) }];

/**
 * The manager's panel, separate from the admin's: statistics of the offices and departments the
 * admin ticked and, with the rights, creating and deleting players there. Every call goes to a
 * manager_* RPC that checks the scope again, so a right the admin took away stops at once; the
 * panel then reloads the scope and hides the buttons.
 */
export function ManagerPanel({ session, onSessionLost }: { session: Session; onSessionLost: () => void }) {
  const { notify } = useDialogs();
  const [profile, setProfile] = useState<ManagerProfile | null>(null);
  const [players, setPlayers] = useState<PlayerSummary[] | null>(null);
  const route = useRoute();

  const reload = useCallback(async () => {
    try {
      const [nextProfile, nextPlayers] = await Promise.all([managerApi.profile(session), managerApi.statsOverview(session)]);
      setProfile(nextProfile);
      setPlayers(nextPlayers);
    } catch (e) {
      if (isSessionError(e)) {
        onSessionLost();
      } else {
        notify(errorText(e), "error");
      }
    }
  }, [session, onSessionLost, notify]);

  const fail = useCallback(
    (e: unknown) => {
      if (isSessionError(e)) {
        onSessionLost();
        return;
      }
      notify(errorText(e), "error");
      if (e instanceof ApiError && (e.key === "manager_right_missing" || e.key === "out_of_scope")) {
        // The admin changed the rights meanwhile.
        void reload();
      }
    },
    [onSessionLost, reload, notify],
  );

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

  const offices = useMemo(() => profile?.offices ?? [], [profile]);
  const departments = useMemo(() => profile?.departments ?? [], [profile]);
  const officeNames = profile?.office_names;
  const officeName = useCallback((id: string) => officeNames?.[id] ?? "—", [officeNames]);
  const departmentName = useCallback((id: string) => departments.find((d) => d.id === id)?.name ?? "—", [departments]);
  const loadPlayerStats = useCallback((userId: string) => managerApi.playerStats(session, userId), [session]);

  const search = useMemo<SearchItem[]>(
    () => [
      { id: "page:overview", group: "Разделы", title: "Обзор", href: "#/", icon: "home" },
      { id: "page:staff", group: "Разделы", title: "Сотрудники", href: href(["staff"]), icon: "users" },
      { id: "page:access", group: "Разделы", title: "Мой доступ", keywords: "права офисы департаменты", href: href(["access"]), icon: "shield" },
      ...(profile?.scope.can_create
        ? [{ id: "new:player", group: "Действия" as const, title: "Добавить сотрудника", keywords: "создать аккаунт", href: href(["staff"], { new: "1" }), icon: "plus" as const }]
        : []),
      ...(players ?? []).map((p) => ({
        id: `player:${p.id}`,
        group: "Сотрудники" as const,
        title: p.display_name || p.username,
        subtitle: `${p.username} · ${officeName(p.office_id)} · ${departmentName(p.department_id)}`,
        keywords: p.status,
        href: href(["staff", p.id]),
        icon: "user" as const,
      })),
      ...departments.map((d) => ({
        id: `department:${d.id}`,
        group: "Департаменты" as const,
        title: d.name,
        subtitle: `Офис «${officeName(d.office_id)}»`,
        href: href(["staff"], { office: d.office_id, department: d.id }),
        icon: "layers" as const,
      })),
    ],
    [profile, players, departments, officeName, departmentName],
  );

  if (!profile) {
    return <Loading text="Загрузка панели…" />;
  }

  const { scope } = profile;
  const actions: DashboardActions = {
    session,
    role: "manager",
    offices,
    departments,
    players,
    officeName,
    departmentName,
    run,
    reload,
    createDepartment: null,
    loadPlayerStats,
    report: fail,
  };

  const nav: NavGroup[] = [
    {
      title: "Моя команда",
      items: [
        { id: "overview", label: "Обзор", icon: "home", href: "#/" },
        { id: "staff", label: "Сотрудники", icon: "users", href: href(["staff"]) },
      ],
    },
    { title: "Аккаунт", items: [{ id: "access", label: "Мой доступ", icon: "shield", href: href(["access"]) }] },
  ];

  const [section = "overview", id = ""] = route.parts;
  const creating = scope.can_create && route.query.get("new") === "1";
  const addButton = scope.can_create ? (
    <button type="button" onClick={() => navigate(href(["staff"], { new: "1" }))}>
      <Icon name="plus" size={16} /> Добавить сотрудника
    </button>
  ) : undefined;
  const scopeText = scopeLabel(scope, offices, departments);

  let page;
  if (section === "staff" && id) {
    page = <PlayerPage key={id} actions={actions} userId={id} base="staff" listLabel="Сотрудники" canDelete={scope.can_delete} />;
  } else if (section === "staff") {
    page = (
      <>
        <PlayersPage
          actions={actions}
          base="staff"
          title="Сотрудники"
          headerActions={addButton}
          onCreate={scope.can_create ? () => navigate(href(["staff"], { new: "1" })) : undefined}
        />
        {creating && (
          <Drawer title="Новый сотрудник" onClose={() => navigate(href(["staff"]))}>
            <CreateUserForm actions={actions} create={(user) => managerApi.createUser(session, user)} onClose={() => navigate(href(["staff"]))} />
          </Drawer>
        )}
      </>
    );
  } else if (section === "access") {
    page = <AccessPage profile={profile} scopeText={scopeText} />;
  } else {
    page = (
      <OverviewPage
        actions={actions}
        title={`Здравствуйте, ${profile.display_name || "руководитель"}`}
        base="staff"
        groupBy="department"
        attention={[]}
        headerActions={addButton}
      />
    );
  }

  return (
    <Shell
      panelLabel="Руководитель"
      accountName={profile.display_name || session.username || "Руководитель"}
      accountRole="Руководитель"
      nav={nav}
      current={section}
      search={search}
      lists={LISTS}
      onSignOut={onSessionLost}
    >
      {page}
    </Shell>
  );
}

function AccessPage({ profile, scopeText }: { profile: ManagerProfile; scopeText: string }) {
  const { scope, offices, departments } = profile;
  const rights = [
    { on: true, text: "Просмотр статистики и журнала сотрудников" },
    { on: scope.can_create, text: "Создание сотрудников и привязка к офису и департаменту" },
    { on: scope.can_delete, text: "Удаление сотрудников" },
  ];
  return (
    <>
      <PageHeader title="Мой доступ" />
      <div className="overview-grid even">
        <section className="card">
          <h2>Офисы и департаменты</h2>
          <p className="muted">{scopeText}</p>
          <ul className="plain-list">
            {offices.map((office) => (
              <li key={office.id}>
                <b>{office.name}</b>
                {office.city && <span className="muted"> · {office.city}</span>}
                <div className="muted">
                  {departments
                    .filter((d) => d.office_id === office.id)
                    .map((d) => d.name)
                    .join(", ") || "нет департаментов"}
                </div>
              </li>
            ))}
          </ul>
        </section>
        <section className="card">
          <h2>Права</h2>
          <ul className="rights-list">
            {rights.map((right) => (
              <li key={right.text} className={right.on ? "on" : "off"}>
                <Icon name={right.on ? "shield" : "ban"} size={16} />
                {right.text}
              </li>
            ))}
          </ul>
        </section>
      </div>
    </>
  );
}
