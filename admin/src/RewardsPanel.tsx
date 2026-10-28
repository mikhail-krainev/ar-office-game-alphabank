import { useCallback, useEffect, useState } from "react";
import { api, type RewardStock, type RewardsOverview } from "./api";
import type { DashboardActions } from "./Dashboard";
import { formatDay } from "./format";
import { RARITY_LABELS, label } from "./labels";

// Server range (server/modules/rewards.go: maxStock).
const MAX_STOCK = 10000;

interface Draft {
  weekly: string;
  left: string;
}

function draftOf(item: RewardStock): Draft {
  return { weekly: String(item.weekly_stock), left: item.left < 0 ? "" : String(item.left) };
}

function stockNumber(text: string): number | null {
  const value = Number(text);
  return text !== "" && Number.isInteger(value) && value >= 0 && value <= MAX_STOCK ? value : null;
}

/**
 * Reward stock and sales: how many of each reward the shop and the fortune wheel may give per week,
 * what is left this week and how many were given in total. The stock is refilled every Monday.
 */
export function RewardsPanel({ actions }: { actions: DashboardActions }) {
  const { session, run, report } = actions;
  const [overview, setOverview] = useState<RewardsOverview | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    try {
      const next = await api.getRewards(session);
      setOverview(next);
      setDrafts(Object.fromEntries(next.items.map((item) => [item.id, draftOf(item)])));
    } catch (e) {
      report(e);
    }
  }, [session, report]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!overview) {
    return (
      <section className="card">
        <h2>Награды</h2>
        <p className="muted">Загрузка…</p>
      </section>
    );
  }

  function edit(id: string, field: keyof Draft, text: string) {
    setNotice("");
    setDrafts((current) => ({ ...current, [id]: { ...current[id], [field]: text } }));
  }

  async function save(item: RewardStock) {
    const draft = drafts[item.id];
    const weekly = stockNumber(draft.weekly);
    const left = weekly === 0 ? 0 : stockNumber(draft.left === "" ? draft.weekly : draft.left);
    if (weekly === null || left === null) {
      return;
    }
    const ok = await run(() => api.setRewardStock(session, item.id, weekly, left));
    if (ok) {
      setNotice(`Запас «${item.name}» сохранён.`);
      await load();
    }
  }

  const totalShop = overview.items.reduce((sum, item) => sum + item.from_shop, 0);
  const totalWheel = overview.items.reduce((sum, item) => sum + item.from_wheel, 0);

  return (
    <section className="card">
      <h2>Награды</h2>
      <p className="muted">
        Запас на неделю пополняется каждый понедельник (неделя с {formatDay(overview.week_start)}). 0 — без ограничений.
        Закончившаяся награда остаётся в магазине и на колесе с пометкой «Нет в наличии»: купить её нельзя, а выигрыш на
        колесе игрок обменивает на монеты по её цене или на повторный спин. Вещи гардероба игрок получает только один раз.
      </p>
      <p className="muted">
        Выдано всего: в магазине {totalShop}, на колесе {totalWheel}; обменено выигрышей колеса: {overview.wheel_exchanged}.
      </p>
      <div className="table-wrap">
        <table className="stats-table">
          <thead>
            <tr>
              <th>Награда</th>
              <th>Редкость</th>
              <th className="num">Цена</th>
              <th className="num">В неделю</th>
              <th className="num">Осталось</th>
              <th className="num">Магазин</th>
              <th className="num">Колесо</th>
              <th className="num">За неделю</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {overview.items.map((item) => {
              const draft = drafts[item.id] ?? draftOf(item);
              const changed = JSON.stringify(draft) !== JSON.stringify(draftOf(item));
              const weekly = stockNumber(draft.weekly);
              const valid = weekly !== null && (weekly === 0 || draft.left === "" || stockNumber(draft.left) !== null);
              return (
                <tr key={item.id}>
                  <td>
                    {item.name}
                    {item.cosmetic && <span className="muted"> · гардероб</span>}
                  </td>
                  <td>{label(RARITY_LABELS, item.rarity)}</td>
                  <td className="num">{item.price}</td>
                  <td className="num">
                    <input
                      className="stock-input"
                      type="number"
                      inputMode="numeric"
                      min={0}
                      max={MAX_STOCK}
                      value={draft.weekly}
                      title={`По умолчанию: ${item.default_stock || "без ограничений"}`}
                      onChange={(e) => edit(item.id, "weekly", e.target.value)}
                    />
                  </td>
                  <td className="num">
                    {weekly === 0 ? (
                      <span className="muted">∞</span>
                    ) : (
                      <input
                        className="stock-input"
                        type="number"
                        inputMode="numeric"
                        min={0}
                        max={MAX_STOCK}
                        value={draft.left}
                        onChange={(e) => edit(item.id, "left", e.target.value)}
                      />
                    )}
                    {item.left === 0 && <span className="hint error"> нет в наличии</span>}
                  </td>
                  <td className="num">{item.from_shop}</td>
                  <td className="num">{item.from_wheel}</td>
                  <td className="num">{item.this_week}</td>
                  <td>
                    <button type="button" className="secondary" disabled={!changed || !valid} onClick={() => void save(item)}>
                      Сохранить
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {notice && <p className="muted">{notice}</p>}
    </section>
  );
}
