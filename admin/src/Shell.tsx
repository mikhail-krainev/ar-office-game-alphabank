import { useEffect, useState, type ReactNode } from "react";
import { AlfaLogo } from "./AlfaLogo";
import { CommandPalette, type ListSearch } from "./CommandPalette";
import { Icon, type IconName } from "./Icon";
import type { SearchItem } from "./search";

export interface NavItem {
  id: string;
  label: string;
  icon: IconName;
  href: string;
  /** A count that needs attention (e.g. rewards out of stock). */
  badge?: number;
}

export interface NavGroup {
  title: string;
  items: NavItem[];
}

/** True when the key goes to a text field, so "/" types a slash there. */
function typingInField(target: EventTarget | null): boolean {
  const element = target as HTMLElement | null;
  return !!element && (element.tagName === "INPUT" || element.tagName === "TEXTAREA" || element.isContentEditable);
}

/**
 * Layout of both panels: the sidebar with the sections, the top bar with the global search and
 * the account, and the page. On a phone the sidebar slides in from the menu button.
 */
export function Shell({
  panelLabel,
  accountName,
  accountRole,
  nav,
  current,
  search,
  lists,
  onSignOut,
  children,
}: {
  panelLabel: string;
  accountName: string;
  accountRole: string;
  nav: NavGroup[];
  current: string;
  search: SearchItem[];
  lists: ListSearch[];
  onSignOut: () => void;
  children: ReactNode;
}) {
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setPaletteOpen((open) => !open);
      } else if (event.key === "/" && !typingInField(event.target)) {
        event.preventDefault();
        setPaletteOpen(true);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => setMenuOpen(false), [current]);

  return (
    <div className={menuOpen ? "shell menu-open" : "shell"}>
      <aside className="sidebar" aria-label="Разделы">
        <a className="brand" href="#/">
          <span className="brand-mark">
            <AlfaLogo size={22} />
          </span>
          <span className="brand-text">
            <span className="brand-name">
              Alfa<span className="brand-accent">Game</span>
            </span>
            <span className="brand-sub">{panelLabel}</span>
          </span>
        </a>
        <div className="sidebar-search">
          <button type="button" className="search-trigger" onClick={() => setPaletteOpen(true)}>
            <Icon name="search" size={16} />
            <span className="search-trigger-text">Поиск</span>
          </button>
        </div>
        <nav className="nav">
          {nav.map((group) => (
            <div key={group.title} className="nav-group">
              <div className="nav-group-title">{group.title}</div>
              {group.items.map((item) => (
                <a key={item.id} href={item.href} className={item.id === current ? "nav-item active" : "nav-item"} aria-current={item.id === current ? "page" : undefined}>
                  <Icon name={item.icon} />
                  <span>{item.label}</span>
                  {item.badge ? <span className="nav-badge">{item.badge}</span> : null}
                </a>
              ))}
            </div>
          ))}
        </nav>
        <div className="sidebar-account">
          <span className="avatar" aria-hidden="true">
            {accountName.trim().charAt(0).toUpperCase() || "?"}
          </span>
          <span className="account-text">
            <span className="account-name">{accountName}</span>
            <span className="account-role">{accountRole}</span>
          </span>
          <button type="button" className="icon-button" title="Выйти" aria-label="Выйти" onClick={onSignOut}>
            <Icon name="logout" />
          </button>
        </div>
      </aside>
      <div className="sidebar-scrim" onClick={() => setMenuOpen(false)} />
      <div className="main">
        <header className="topbar">
          <button type="button" className="icon-button menu-button" aria-label="Меню" onClick={() => setMenuOpen(true)}>
            <Icon name="menu" />
          </button>
          <a className="topbar-brand" href="#/">
            <span className="brand-mark small">
              <AlfaLogo size={16} />
            </span>
            <span className="brand-name">
              Alfa<span className="brand-accent">Game</span>
            </span>
          </a>
          <button type="button" className="icon-button" aria-label="Поиск" onClick={() => setPaletteOpen(true)}>
            <Icon name="search" />
          </button>
        </header>
        <main className="content">{children}</main>
      </div>
      {paletteOpen && <CommandPalette items={search} lists={lists} onClose={() => setPaletteOpen(false)} />}
    </div>
  );
}
