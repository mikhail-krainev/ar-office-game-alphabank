import { useState, type FormEvent } from "react";
import { api, managerApi, type PlayerSummary } from "./api";
import type { DashboardActions } from "./actions";
import { PlayBadge, PresenceBadge } from "./badges";
import { ResetPasswordForm } from "./Credentials";
import { DepartmentSelect } from "./DepartmentSelect";
import { useDialogs } from "./Dialogs";
import { formatDateTime } from "./format";
import { Icon } from "./Icon";
import { OfficeSelect } from "./OfficeSelect";
import { PlayerStats } from "./PlayerStats";
import { href, navigate } from "./router";
import { TripForm, tripLabel } from "./TripForm";
import { Drawer, EmptyState, Loading, PageHeader } from "./ui";

type Panel = "edit" | "trip" | "password" | null;

/**
 * One player: who they are and where, the account actions on top (the admin: placement, trip,
 * password, block, delete; a manager: delete with the right) and the full activity audit below.
 */
export function PlayerPage({
  actions,
  userId,
  base,
  listLabel,
  canDelete,
}: {
  actions: DashboardActions;
  userId: string;
  base: string;
  listLabel: string;
  canDelete: boolean;
}) {
  const { players, session, run, officeName, departmentName, role } = actions;
  const { confirm, notify } = useDialogs();
  const [panel, setPanel] = useState<Panel>(null);
  const [version, setVersion] = useState(0);
  const player = players?.find((p) => p.id === userId);
  const isAdmin = role === "admin";
  const crumbs = [{ label: listLabel, href: href([base]) }];

  if (players === null) {
    return <Loading />;
  }
  if (!player) {
    return (
      <>
        <PageHeader title="Сотрудник не найден" crumbs={crumbs} />
        <EmptyState icon="user" title="Такого сотрудника нет или он вне вашего доступа">
          <a href={href([base])}>Вернуться к списку</a>
        </EmptyState>
      </>
    );
  }

  async function act(action: () => Promise<unknown>, done: string) {
    if (await run(action)) {
      setVersion((v) => v + 1);
      notify(done);
      return true;
    }
    return false;
  }

  async function toggleBan(p: PlayerSummary) {
    const ok = await confirm(
      p.banned
        ? { title: "Вернуть доступ?", text: `${p.display_name} снова сможет входить в игру.`, confirmLabel: "Разблокировать" }
        : {
            title: "Заблокировать сотрудника?",
            text: `${p.display_name} не сможет входить в игру, открытые сессии завершатся сразу. Прогресс сохранится.`,
            confirmLabel: "Заблокировать",
            danger: true,
          },
    );
    if (ok) {
      await act(() => api.setBanned(session, p.id, !p.banned), p.banned ? "Доступ возвращён." : "Сотрудник заблокирован.");
    }
  }

  async function remove(p: PlayerSummary) {
    const ok = await confirm({
      title: "Удалить аккаунт?",
      text: (
        <>
          Аккаунт <b>{p.display_name}</b> (<code>{p.username}</code>) удалится вместе с прогрессом, монетами и историей. Отменить
          нельзя.
        </>
      ),
      confirmLabel: "Удалить навсегда",
      danger: true,
    });
    if (!ok) {
      return;
    }
    const del = isAdmin ? () => api.deleteUser(session, p.id) : () => managerApi.deleteUser(session, p.id);
    if (await run(del)) {
      notify(`Аккаунт ${p.username} удалён.`);
      navigate(href([base]));
    }
  }

  async function endTrip(p: PlayerSummary) {
    const ok = await confirm({
      title: "Завершить командировку?",
      text: `С этого момента ${p.display_name} снова в своём офисе.`,
      confirmLabel: "Завершить",
    });
    if (ok) {
      await act(() => api.setTrip(session, p.id, { office_id: "", department_id: "", until: "" }), "Командировка завершена.");
    }
  }

  return (
    <>
      <PageHeader
        crumbs={crumbs}
        title={
          <span className="title-with-badges">
            {player.display_name}
            <PresenceBadge player={player} />
            <PlayBadge player={player} />
          </span>
        }
        description={
          <>
            <code>{player.username}</code> · {officeName(player.office_id)} · {departmentName(player.department_id)} · создан{" "}
            {formatDateTime(player.created_at)}
          </>
        }
        actions={
          <>
            {isAdmin && (
              <>
                <button type="button" className="secondary" onClick={() => setPanel("edit")}>
                  <Icon name="edit" size={16} /> Изменить
                </button>
                <button type="button" className="secondary" onClick={() => setPanel("trip")} disabled={actions.offices.length < 2}>
                  <Icon name="plane" size={16} /> Командировка
                </button>
                <button type="button" className="secondary" onClick={() => setPanel("password")}>
                  <Icon name="key" size={16} /> Пароль
                </button>
                <button type="button" className="secondary" onClick={() => void toggleBan(player)}>
                  <Icon name="ban" size={16} /> {player.banned ? "Разблокировать" : "Заблокировать"}
                </button>
              </>
            )}
            {canDelete && (
              <button type="button" className="danger" onClick={() => void remove(player)}>
                <Icon name="trash" size={16} /> Удалить
              </button>
            )}
          </>
        }
      >
        {(player.trip || player.guest_office_id) && (
          <div className="notice">
            {player.trip && (
              <span>
                <Icon name="plane" size={16} /> В командировке: {tripLabel(actions, player.trip)}
                {isAdmin && (
                  <button type="button" className="link" onClick={() => void endTrip(player)}>
                    завершить
                  </button>
                )}
              </span>
            )}
            {player.guest_office_id && (
              <span>
                <Icon name="wifi" size={16} /> Сегодня в офисе «{officeName(player.guest_office_id)}» (по Wi-Fi)
              </span>
            )}
          </div>
        )}
      </PageHeader>

      <PlayerStats actions={actions} userId={player.id} version={version} />

      {panel === "edit" && (
        <Drawer title="Изменить сотрудника" onClose={() => setPanel(null)}>
          <EditPlayerForm
            actions={actions}
            player={player}
            onSave={async (changes) => {
              if (await act(() => api.updateUser(session, player.id, changes), "Изменения сохранены.")) {
                setPanel(null);
              }
            }}
            onCancel={() => setPanel(null)}
          />
        </Drawer>
      )}
      {panel === "trip" && (
        <Drawer title={player.trip ? "Изменить командировку" : "Отправить в командировку"} onClose={() => setPanel(null)}>
          <TripForm
            actions={actions}
            player={player}
            onDone={() => {
              setVersion((v) => v + 1);
              setPanel(null);
            }}
          />
        </Drawer>
      )}
      {panel === "password" && (
        <Drawer title="Сменить пароль" onClose={() => setPanel(null)}>
          <ResetPasswordForm
            name={player.display_name}
            username={player.username}
            save={(password) => run(() => api.setPassword(session, player.id, password))}
            onDone={() => setPanel(null)}
          />
        </Drawer>
      )}
    </>
  );
}

function EditPlayerForm({
  actions,
  player,
  onSave,
  onCancel,
}: {
  actions: DashboardActions;
  player: PlayerSummary;
  onSave: (changes: { display_name?: string; office_id?: string; department_id?: string }) => Promise<void>;
  onCancel: () => void;
}) {
  const [name, setName] = useState(player.display_name);
  const [officeId, setOfficeId] = useState(player.office_id);
  const [departmentId, setDepartmentId] = useState(player.department_id);
  const changed = name.trim() !== player.display_name || officeId !== player.office_id || departmentId !== player.department_id;

  function submit(event: FormEvent) {
    event.preventDefault();
    const changes: { display_name?: string; office_id?: string; department_id?: string } = {};
    if (name.trim() !== player.display_name) {
      changes.display_name = name.trim();
    }
    if (officeId !== player.office_id) {
      changes.office_id = officeId;
    }
    if (departmentId !== player.department_id || officeId !== player.office_id) {
      changes.department_id = departmentId;
    }
    void onSave(changes);
  }

  return (
    <form className="stack-form" onSubmit={submit}>
      <label>
        Имя и фамилия
        <input value={name} onChange={(e) => setName(e.target.value)} maxLength={60} required />
      </label>
      <label>
        Домашний офис
        <OfficeSelect
          actions={actions}
          value={officeId}
          onChange={(id) => {
            setOfficeId(id);
            setDepartmentId("");
          }}
        />
      </label>
      <label>
        Департамент
        <DepartmentSelect actions={actions} officeId={officeId} value={departmentId} onChange={setDepartmentId} />
        <span className="hint">По домашнему офису считаются статистика и розыгрыш парковки.</span>
      </label>
      <div className="form-actions">
        <button type="submit" disabled={!changed || !departmentId || !name.trim()}>
          Сохранить
        </button>
        <button type="button" className="secondary" onClick={onCancel}>
          Отмена
        </button>
      </div>
    </form>
  );
}
