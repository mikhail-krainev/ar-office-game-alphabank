import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type RewardStock, type RewardsOverview } from "./api";
import type { DashboardActions } from "./actions";
import { useDialogs } from "./Dialogs";
import { FilterBar, matches, useFilters } from "./FilterBar";
import { Icon } from "./Icon";
import { EmptyState, Loading, PageHeader, StatCard } from "./ui";
import { formatDay } from "./format";
import { RARITY_LABELS, label } from "./labels";

// Server range (server/modules/rewards.go: maxStock).
const MAX_STOCK = 10000;

const DEFAULT_FILTERS = { q: "", stock: "", rarity: "", kind: "" };

type StockState = "in" | "out" | "unlimited";
const STOCK_LABELS: Record<StockState, string> = { in: "в наличии", out: "нет в наличии", unlimited: "без ограничений" };

function stockState(item: RewardStock): StockState {
  if (item.left < 0) {
    return "unlimited";
  }
  return item.left === 0 ? "out" : "in";
}

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
  const { notify } = useDialogs();
  const [overview, setOverview] = useState<RewardsOverview | null>(null);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const { values, set, reset, active } = useFilters("rewards", DEFAULT_FILTERS);

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

  const visible = useMemo(
    () =>
      (overview?.items ?? [])
        .filter((item) => !values.rarity || item.rarity === values.rarity)
        .filter((item) => !values.stock || stockState(item) === values.stock)
        .filter((item) => !values.kind || (values.kind === "cosmetic") === item.cosmetic)
        .filter((item) => matches(values.q, item.name, item.id, label(RARITY_LABELS, item.rarity))),
    [overview, values],
  );

  const header = (
    <PageHeader
      title="Награды"
      actions={
        <button type="button" className="secondary" onClick={() => void load()}>
          <Icon name="refresh" size={16} /> Обновить
        </button>
      }
    />
  );

  if (!overview) {
    return (
      <>
        {header}
        <Loading />
      </>
    );
  }

  function edit(id: string, field: keyof Draft, text: string) {
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
      notify(`Запас «${item.name}» сохранён.`);
      await load();
    }
  }

  const totalShop = overview.items.reduce((sum, item) => sum + item.from_shop, 0);
  const totalWheel = overview.items.reduce((sum, item) => sum + item.from_wheel, 0);
  const outOfStock = overview.items.filter((item) => item.left === 0).length;
  const rarities = [...new Set(overview.items.map((item) => item.rarity))];

  return (
    <>
      {header}
      <div className="stat-grid">
        <StatCard label="Неделя с" value={formatDay(overview.week_start)} />
        <StatCard label="Выдано в магазине" value={totalShop} />
        <StatCard label="Выдано на колесе" value={totalWheel} hint={`обменено выигрышей: ${overview.wheel_exchanged}`} />
        <StatCard
          label="Нет в наличии"
          value={outOfStock}
          tone={outOfStock ? "warn" : undefined}
          href={outOfStock ? "#/rewards?stock=out" : undefined}
        />
      </div>
      <section className="card flush">
        <FilterBar
          query={values.q}
          onQuery={(text) => set("q", text)}
          placeholder="Название награды"
          filters={[
            { key: "stock", label: "Наличие", allLabel: "любое", options: Object.entries(STOCK_LABELS).map(([value, text]) => ({ value, label: text })) },
            { key: "rarity", label: "Редкость", allLabel: "любая", options: rarities.map((r) => ({ value: r, label: label(RARITY_LABELS, r) })) },
            {
              key: "kind",
              label: "Тип",
              allLabel: "все",
              options: [
                { value: "cosmetic", label: "гардероб" },
                { value: "other", label: "прочие" },
              ],
            },
          ]}
          values={values}
          onChange={(key, value) => set(key as keyof typeof DEFAULT_FILTERS, value)}
          onReset={reset}
          active={active}
          shown={visible.length}
          total={overview.items.length}
          noun={["награда", "награды", "наград"]}
        />
        {visible.length === 0 ? (
          <EmptyState icon="gift" title="Наград не найдено">
            <button type="button" className="link" onClick={reset}>
              Сбросить фильтры
            </button>
          </EmptyState>
        ) : (
      <div className="table-wrap">
        <table className="data-table">
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
            {visible.map((item) => {
              const draft = drafts[item.id] ?? draftOf(item);
              const changed = JSON.stringify(draft) !== JSON.stringify(draftOf(item));
              const weekly = stockNumber(draft.weekly);
              const valid = weekly !== null && (weekly === 0 || draft.left === "" || stockNumber(draft.left) !== null);
              return (
                <tr key={item.id}>
                  <td>
                    <span className="player-name">{item.name}</span>
                    {item.cosmetic && <span className="muted">гардероб</span>}
                  </td>
                  <td>
                    <span className={`badge rarity-${item.rarity}`}>{label(RARITY_LABELS, item.rarity)}</span>
                  </td>
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
                    {item.left === 0 && <div className="hint error">нет в наличии</div>}
                  </td>
                  <td className="num">{item.from_shop}</td>
                  <td className="num">{item.from_wheel}</td>
                  <td className="num">{item.this_week}</td>
                  <td>
                    <button type="button" className={changed ? "small" : "secondary small"} disabled={!changed || !valid} onClick={() => void save(item)}>
                      Сохранить
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
        )}
      </section>
    </>
  );
}
