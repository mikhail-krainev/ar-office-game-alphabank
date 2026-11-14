import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { Icon } from "./Icon";
import { navigate } from "./router";
import { searchItems, type SearchItem } from "./search";

/** A list page that can take the query as its search filter ("#/players?q=…"). */
export interface ListSearch {
  label: string;
  href: (query: string) => string;
}

/**
 * Global search of the panel (⌘K / Ctrl+K or "/"): pages, players, managers, offices,
 * departments and rewards in one list; Enter or a click opens the object.
 */
export function CommandPalette({
  items,
  lists,
  onClose,
}: {
  items: SearchItem[];
  lists: ListSearch[];
  onClose: () => void;
}) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const listRef = useRef<HTMLDivElement>(null);

  const sections = useMemo(() => {
    const found = searchItems(items, query);
    const text = query.trim();
    if (!text) {
      return found;
    }
    const inLists: SearchItem[] = lists.map((list) => ({
      id: `list:${list.label}`,
      group: "Действия",
      title: `Искать «${text}» ${list.label}`,
      href: list.href(text),
      icon: "filter",
    }));
    const rest = found.filter((section) => section.group !== "Действия");
    const actions = found.find((section) => section.group === "Действия")?.items ?? [];
    return [...rest, { group: "Действия" as const, items: [...actions, ...inLists] }];
  }, [items, lists, query]);

  const flat = sections.flatMap((section) => section.items);

  useEffect(() => setActive(0), [query]);

  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
  }, [active]);

  function open(item: SearchItem) {
    onClose();
    navigate(item.href);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActive((index) => Math.min(index + 1, flat.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActive((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (flat[active]) {
        open(flat[active]);
      }
    } else if (event.key === "Escape") {
      event.preventDefault();
      onClose();
    }
  }

  let index = -1;
  return (
    <div className="overlay palette-overlay" onMouseDown={onClose}>
      <div className="palette" role="dialog" aria-modal="true" aria-label="Поиск по панели" onMouseDown={(e) => e.stopPropagation()}>
        <div className="palette-input">
          <Icon name="search" />
          <input
            autoFocus
            placeholder="Сотрудник, логин, офис, департамент, награда или раздел…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onKeyDown}
            role="combobox"
            aria-expanded="true"
            aria-controls="palette-results"
            aria-activedescendant={flat[active] ? `palette-${active}` : undefined}
            spellCheck={false}
            autoComplete="off"
          />
          <kbd>Esc</kbd>
        </div>
        <div className="palette-results" id="palette-results" role="listbox" ref={listRef}>
          {flat.length === 0 && <p className="palette-empty muted">Ничего не найдено. Попробуйте имя, логин или название.</p>}
          {sections.map((section) => (
            <div key={section.group} className="palette-group">
              <div className="palette-group-title">{section.group}</div>
              {section.items.map((item) => {
                index += 1;
                const itemIndex = index;
                return (
                  <div
                    key={item.id}
                    id={`palette-${itemIndex}`}
                    data-index={itemIndex}
                    role="option"
                    aria-selected={itemIndex === active}
                    className={itemIndex === active ? "palette-item active" : "palette-item"}
                    onMouseMove={() => setActive(itemIndex)}
                    onClick={() => open(item)}
                  >
                    <span className="palette-icon">
                      <Icon name={item.icon} size={16} />
                    </span>
                    <span className="palette-text">
                      <span className="palette-title">{item.title}</span>
                      {item.subtitle && <span className="palette-subtitle">{item.subtitle}</span>}
                    </span>
                    {itemIndex === active && <Icon name="chevronRight" size={16} />}
                  </div>
                );
              })}
            </div>
          ))}
        </div>
        <div className="palette-footer muted">
          <span>
            <kbd>↑</kbd> <kbd>↓</kbd> выбор
          </span>
          <span>
            <kbd>Enter</kbd> открыть
          </span>
        </div>
      </div>
    </div>
  );
}
