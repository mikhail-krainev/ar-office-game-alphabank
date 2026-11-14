import { useEffect, type ReactNode } from "react";
import { Icon, type IconName } from "./Icon";

/** Page title with the breadcrumb above it and the page actions on the right. */
export function PageHeader({
  title,
  description,
  crumbs,
  actions,
  children,
}: {
  title: ReactNode;
  description?: ReactNode;
  /** Parent pages, nearest last. */
  crumbs?: { label: string; href: string }[];
  actions?: ReactNode;
  children?: ReactNode;
}) {
  return (
    <header className="page-header">
      {crumbs && crumbs.length > 0 && (
        <nav className="crumbs" aria-label="Навигация">
          {crumbs.map((crumb) => (
            <span key={crumb.href}>
              <a href={crumb.href}>{crumb.label}</a>
              <Icon name="chevronRight" size={14} />
            </span>
          ))}
        </nav>
      )}
      <div className="page-title-row">
        <div className="page-title">
          <h1>{title}</h1>
          {description && <p className="muted">{description}</p>}
        </div>
        {actions && <div className="page-actions">{actions}</div>}
      </div>
      {children}
    </header>
  );
}

/** Side panel for creating and editing: the list stays visible behind it. */
export function Drawer({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
      }
    };
    document.addEventListener("keydown", onKey);
    document.body.classList.add("no-scroll");
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.classList.remove("no-scroll");
    };
  }, [onClose]);

  return (
    <div className="overlay drawer-overlay" onMouseDown={onClose}>
      <aside
        className={wide ? "drawer wide" : "drawer"}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onMouseDown={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <h2>{title}</h2>
          <button type="button" className="icon-button" aria-label="Закрыть" onClick={onClose}>
            <Icon name="x" />
          </button>
        </div>
        <div className="drawer-body">{children}</div>
      </aside>
    </div>
  );
}

export function EmptyState({ icon = "search", title, children }: { icon?: IconName; title: string; children?: ReactNode }) {
  return (
    <div className="empty-state">
      <span className="empty-icon">
        <Icon name={icon} size={22} />
      </span>
      <b>{title}</b>
      {children && <div className="muted">{children}</div>}
    </div>
  );
}

/** Longer values (a date) get a smaller font so they fit the card. */
const LONG_STAT_VALUE = 6;

/** A number of the overview; with `href` the card opens the list it counts. */
export function StatCard({
  label,
  value,
  hint,
  href,
  tone,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  href?: string;
  tone?: "accent" | "good" | "warn";
}) {
  const body = (
    <>
      <span className="stat-label">{label}</span>
      <span className={typeof value === "string" && value.length > LONG_STAT_VALUE ? "stat-value long" : "stat-value"}>{value}</span>
      {hint && <span className="stat-hint">{hint}</span>}
    </>
  );
  const className = `stat-card${tone ? ` ${tone}` : ""}`;
  return href ? (
    <a className={`${className} link-card`} href={href}>
      {body}
    </a>
  ) : (
    <div className={className}>{body}</div>
  );
}

/** Tabs that are addresses: a tab can be opened from the search or a link. */
export function TabLinks({ tabs, current }: { tabs: { id: string; label: ReactNode; href: string; icon?: IconName }[]; current: string }) {
  return (
    <nav className="tabs" role="tablist">
      {tabs.map((tab) => (
        <a key={tab.id} role="tab" aria-selected={tab.id === current} className={tab.id === current ? "tab active" : "tab"} href={tab.href}>
          {tab.icon && <Icon name={tab.icon} size={16} />}
          {tab.label}
        </a>
      ))}
    </nav>
  );
}

export function Loading({ text = "Загрузка…" }: { text?: string }) {
  return (
    <div className="loading">
      <span className="spinner" aria-hidden="true" />
      {text}
    </div>
  );
}
