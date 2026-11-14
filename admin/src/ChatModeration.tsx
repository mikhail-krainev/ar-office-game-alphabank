import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type ChatMessage, type Office } from "./api";
import type { DashboardActions } from "./actions";
import { useDialogs } from "./Dialogs";
import { FilterBar, matches } from "./FilterBar";
import { formatDateTime } from "./format";
import { Icon } from "./Icon";
import { EmptyState, Loading } from "./ui";

const DAY_SECONDS = 86400;
const PERIODS = [
  { value: "1", label: "за сутки" },
  { value: "3", label: "за 3 дня" },
];

/**
 * Messages of an office chat or of one of its department chats for the last week; the admin finds
 * an unsuitable one by text, author or time and removes it. Direct messages stay private.
 */
export function ChatModeration({ actions, office }: { actions: DashboardActions; office: Office }) {
  const { session, departments, run, report } = actions;
  const { confirm, notify } = useDialogs();
  const [chat, setChat] = useState("");
  const [messages, setMessages] = useState<ChatMessage[] | null>(null);
  const [filters, setFilters] = useState({ q: "", author: "", period: "" });
  const officeDepartments = departments.filter((department) => department.office_id === office.id);

  const load = useCallback(
    async (department: string) => {
      try {
        setMessages(await api.getChatMessages(session, office.id, department));
      } catch (error) {
        report(error);
      }
    },
    [session, office.id, report],
  );

  useEffect(() => {
    setMessages(null);
    void load(chat);
  }, [load, chat]);

  const authors = useMemo(
    () => [...new Map((messages ?? []).map((m) => [m.sender_id, m.name])).entries()].map(([value, label]) => ({ value, label })),
    [messages],
  );

  const visible = useMemo(() => {
    const since = filters.period ? Date.now() / 1000 - Number(filters.period) * DAY_SECONDS : 0;
    return [...(messages ?? [])]
      .reverse()
      .filter((m) => !filters.author || m.sender_id === filters.author)
      .filter((m) => m.at >= since)
      .filter((m) => matches(filters.q, m.text, m.name));
  }, [messages, filters]);

  async function remove(message: ChatMessage) {
    const ok = await confirm({
      title: "Удалить сообщение?",
      text: (
        <>
          «{message.text}» от {message.name}. Сообщение пропадёт у всех игроков.
        </>
      ),
      confirmLabel: "Удалить",
      danger: true,
    });
    if (ok && (await run(() => api.deleteChatMessage(session, office.id, chat, message.id)))) {
      notify("Сообщение удалено.");
      await load(chat);
    }
  }

  const active = (filters.author ? 1 : 0) + (filters.period ? 1 : 0);

  return (
    <section className="card flush">
      <div className="card-head">
        <div>
          <h2>Модерация чата</h2>
        </div>
      </div>
      <FilterBar
        query={filters.q}
        onQuery={(q) => setFilters({ ...filters, q })}
        placeholder="Текст сообщения или автор"
        filters={[
          {
            key: "chat",
            label: "Чат",
            allLabel: "общий чат офиса",
            options: officeDepartments.map((department) => ({ value: department.id, label: `отдел «${department.name}»` })),
          },
          { key: "author", label: "Автор", allLabel: "все", options: authors },
          { key: "period", label: "Период", allLabel: "за неделю", options: PERIODS },
        ]}
        values={{ ...filters, chat }}
        onChange={(key, value) => {
          if (key === "chat") {
            setChat(value);
            setFilters({ ...filters, author: "" });
          } else {
            setFilters({ ...filters, [key]: value });
          }
        }}
        onReset={() => setFilters({ q: "", author: "", period: "" })}
        active={active}
        shown={visible.length}
        total={messages?.length ?? 0}
        noun={["сообщение", "сообщения", "сообщений"]}
      />
      {messages === null ? (
        <Loading />
      ) : visible.length === 0 ? (
        <EmptyState icon="chat" title={messages.length === 0 ? "Сообщений нет" : "Ничего не найдено"} />
      ) : (
        <div className="table-wrap">
          <table className="data-table">
            <thead>
              <tr>
                <th>Время</th>
                <th>Автор</th>
                <th>Сообщение</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {visible.map((message) => (
                <tr key={message.id}>
                  <td className="nowrap">{formatDateTime(message.at)}</td>
                  <td className="nowrap">
                    <a href={`#/players/${encodeURIComponent(message.sender_id)}`}>{message.name}</a>
                  </td>
                  <td className="message-text">{message.text}</td>
                  <td className="actions">
                    <button type="button" className="secondary small" onClick={() => void remove(message)}>
                      <Icon name="trash" size={14} /> Удалить
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
