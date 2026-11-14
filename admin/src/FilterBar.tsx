import { useEffect, type ReactNode } from "react";
import { Dropdown } from "./Dropdown";
import { plural } from "./format";
import { Icon } from "./Icon";
import { parseRoute, useRoute } from "./router";
import { usePersisted } from "./usePersisted";

export interface FilterOption {
  value: string;
  label: string;
}

/** One filter of a list; the empty value means "all". */
export interface FilterDef {
  key: string;
  label: string;
  options: FilterOption[];
  /** Label of the empty value; "Все" by default. */
  allLabel?: string;
}

export type FilterValues = Record<string, string>;

/**
 * Filters of one list: kept for the tab session (coming back from an object keeps them) and
 * preset by the address, so a card of the overview opens the list already filtered
 * ("#/players?presence=on_site"). The preset is taken and removed from the address.
 */
export function useFilters<T extends FilterValues>(key: string, defaults: T) {
  const [values, setValues] = usePersisted<T>(`filters:${key}`, defaults);
  const search = useRoute().query.toString();

  useEffect(() => {
    const route = parseRoute(window.location.hash);
    const preset = Object.keys(defaults).filter((name) => route.query.has(name));
    if (preset.length === 0) {
      return;
    }
    const next = { ...defaults } as FilterValues;
    for (const name of preset) {
      next[name] = route.query.get(name) ?? "";
    }
    setValues(next as T);
    for (const name of preset) {
      route.query.delete(name);
    }
    const rest = route.query.toString();
    window.history.replaceState(null, "", `#/${route.parts.map(encodeURIComponent).join("/")}${rest ? `?${rest}` : ""}`);
    // Only when the address brings a preset: later the admin changes the filters by hand.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  const set = (name: keyof T, value: string) => setValues({ ...values, [name]: value });
  const update = (changes: Partial<T>) => setValues({ ...values, ...changes });
  const reset = () => setValues(defaults);
  const active = (Object.keys(defaults) as (keyof T)[]).filter((name) => name !== "sort" && name !== "q" && values[name] !== defaults[name]).length;
  return { values, set, update, reset, active };
}

/** Normalized text for matching: lower case, "ё" as "е". */
export function normalize(text: string): string {
  return text.toLowerCase().replace(/ё/g, "е").trim();
}

/** Every word of the query is found in one of the texts. */
export function matches(query: string, ...texts: (string | undefined)[]): boolean {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return true;
  }
  const haystack = normalize(texts.filter(Boolean).join(" "));
  return words.every((word) => haystack.includes(word));
}

/**
 * The bar above a list: text search, filter menus (a narrowing one is highlighted), the count of
 * shown rows and one button that clears everything.
 */
export function FilterBar({
  query,
  onQuery,
  placeholder,
  filters,
  values,
  onChange,
  onReset,
  active,
  shown,
  total,
  noun,
  extra,
}: {
  query: string;
  onQuery: (text: string) => void;
  placeholder: string;
  filters: FilterDef[];
  values: FilterValues;
  onChange: (key: string, value: string) => void;
  onReset: () => void;
  /** Number of filters (and the search) that narrow the list. */
  active: number;
  shown: number;
  total: number;
  /** Plural forms of the row noun: ["сотрудник", "сотрудника", "сотрудников"]. */
  noun: [string, string, string];
  /** Sorting and other controls on the right. */
  extra?: ReactNode;
}) {
  const narrowed = active > 0 || query.trim() !== "";
  return (
    <div className="filter-bar">
      <div className="filter-controls">
        <label className="search-field">
          <Icon name="search" size={16} />
          <input type="search" placeholder={placeholder} value={query} onChange={(e) => onQuery(e.target.value)} aria-label={placeholder} />
          {query && (
            <button type="button" className="icon-button" aria-label="Очистить поиск" onClick={() => onQuery("")}>
              <Icon name="x" size={14} />
            </button>
          )}
        </label>
        {filters.map((filter) => (
          <div className="filter-item" key={filter.key}>
            <Dropdown
              prefix={filter.label}
              value={values[filter.key] ?? ""}
              placeholder={filter.allLabel ?? "Все"}
              highlighted={(values[filter.key] ?? "") !== ""}
              options={[{ value: "", label: filter.allLabel ?? "Все" }, ...filter.options]}
              onChange={(value) => onChange(filter.key, value)}
            />
          </div>
        ))}
        {extra}
      </div>
      <div className="filter-summary">
        <span className="muted">
          {narrowed ? `Найдено ${shown} из ${total}` : `${total} ${plural(total, ...noun)}`}
        </span>
        {narrowed && (
          <button type="button" className="link" onClick={onReset}>
            Сбросить фильтры
          </button>
        )}
      </div>
    </div>
  );
}
