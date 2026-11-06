import { useEffect, useState } from "react";
import { api, type ChatMessage, type Office } from "./api";
import type { DashboardActions } from "./Dashboard";
import { formatDateTime } from "./format";

/**
 * Messages of an office chat or of one of its department chats for the last week; the admin removes
 * an unsuitable message. Direct messages between players stay private and are not shown here.
 */
export function ChatModeration({ actions, office, onClose }: { actions: DashboardActions; office: Office; onClose: () => void }) {
  const { session, departments, run, report } = actions;
  const [departmentId, setDepartmentId] = useState("");
  const [messages, setMessages] = useState<ChatMessage[] | null>(null);
  const officeDepartments = departments.filter((department) => department.office_id === office.id);

  async function load(department: string) {
    try {
      setMessages(await api.getChatMessages(session, office.id, department));
    } catch (error) {
      report(error);
    }
  }

  useEffect(() => {
    setMessages(null);
    void load(departmentId);
  }, [office.id, departmentId]);

  async function remove(message: ChatMessage) {
    if (!window.confirm(`Удалить сообщение «${message.text}» от ${message.name}? Оно пропадёт у всех игроков.`)) {
      return;
    }
    if (await run(() => api.deleteChatMessage(session, office.id, departmentId, message.id))) {
      await load(departmentId);
    }
  }

  return (
    <>
      <h3>Чат офиса «{office.name}»</h3>
      <p className="muted">
        Сообщения за последние 7 дней (старые удаляются сами). Личные сообщения игроков здесь не показываются.
      </p>
      <label>
        Чат{" "}
        <select value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
          <option value="">Общий чат офиса</option>
          {officeDepartments.map((department) => (
            <option key={department.id} value={department.id}>
              Отдел: {department.name}
            </option>
          ))}
        </select>
      </label>
      {messages === null ? (
        <p className="hint">Загружаю…</p>
      ) : messages.length === 0 ? (
        <p className="hint">Сообщений нет.</p>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Время</th>
                <th>Автор</th>
                <th>Сообщение</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {[...messages].reverse().map((message) => (
                <tr key={message.id}>
                  <td className="nowrap">{formatDateTime(message.at)}</td>
                  <td className="nowrap">{message.name}</td>
                  <td>{message.text}</td>
                  <td className="actions">
                    <button className="secondary" onClick={() => remove(message)}>
                      Удалить
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="form-actions">
        <button type="button" className="secondary" onClick={onClose}>
          Закрыть
        </button>
      </div>
    </>
  );
}
