import { useEffect, useId, useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";

export interface DropdownOption {
  value: string;
  label: string;
  /** Rendered as an action (e.g. "+ New …") rather than a plain choice. */
  action?: boolean;
}

const MENU_MAX_HEIGHT = 280;
const GAP = 4;

/**
 * Themed replacement for a native select. The menu is portalled to the body so the
 * scrolling table does not clip it; focus stays on the trigger (aria-activedescendant).
 */
export function Dropdown({
  value,
  options,
  placeholder,
  onChange,
  prefix,
  highlighted,
  ariaLabel,
}: {
  value: string;
  options: DropdownOption[];
  placeholder: string;
  onChange: (value: string) => void;
  /** Label shown before the value ("Офис: Екатеринбург"), for filters. */
  prefix?: string;
  /** Marks a filter that narrows the list. */
  highlighted?: boolean;
  ariaLabel?: string;
}) {
  const id = useId();
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLUListElement>(null);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const [position, setPosition] = useState<CSSProperties>({});

  const selected = options.find((option) => option.value === value && !option.action);

  function show() {
    const index = options.findIndex((option) => option.value === value);
    setActive(Math.max(index, 0));
    setOpen(true);
  }

  function choose(option: DropdownOption) {
    setOpen(false);
    if (option.action || option.value !== value) {
      onChange(option.value);
    }
  }

  useLayoutEffect(() => {
    if (!open || !triggerRef.current) {
      return;
    }
    const rect = triggerRef.current.getBoundingClientRect();
    const below = window.innerHeight - rect.bottom;
    const style: CSSProperties = { left: rect.left, minWidth: rect.width, maxHeight: MENU_MAX_HEIGHT };
    if (below < MENU_MAX_HEIGHT + GAP && rect.top > below) {
      style.bottom = window.innerHeight - rect.top + GAP;
    } else {
      style.top = rect.bottom + GAP;
    }
    setPosition(style);
  }, [open]);

  useEffect(() => {
    if (!open) {
      return;
    }
    const close = (event: Event) => {
      const target = event.target as Node;
      if (!menuRef.current?.contains(target) && !triggerRef.current?.contains(target)) {
        setOpen(false);
      }
    };
    const closeAlways = () => setOpen(false);
    document.addEventListener("mousedown", close);
    document.addEventListener("scroll", close, true);
    window.addEventListener("resize", closeAlways);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("scroll", close, true);
      window.removeEventListener("resize", closeAlways);
    };
  }, [open]);

  useEffect(() => {
    if (open) {
      menuRef.current?.children[active]?.scrollIntoView({ block: "nearest" });
    }
  }, [open, active]);

  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (!open) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].includes(event.key)) {
        event.preventDefault();
        show();
      }
      return;
    }
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        setActive((index) => Math.min(index + 1, options.length - 1));
        break;
      case "ArrowUp":
        event.preventDefault();
        setActive((index) => Math.max(index - 1, 0));
        break;
      case "Home":
        event.preventDefault();
        setActive(0);
        break;
      case "End":
        event.preventDefault();
        setActive(options.length - 1);
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        if (options[active]) {
          choose(options[active]);
        }
        break;
      case "Escape":
        event.preventDefault();
        setOpen(false);
        break;
      case "Tab":
        setOpen(false);
        break;
    }
  }

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        className={`dropdown-trigger${open ? " open" : ""}${highlighted ? " highlighted" : ""}`}
        aria-label={ariaLabel ?? prefix}
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? `${id}-menu` : undefined}
        aria-activedescendant={open ? `${id}-${active}` : undefined}
        onClick={() => (open ? setOpen(false) : show())}
        onKeyDown={onKeyDown}
      >
        {prefix && <span className="dropdown-prefix">{prefix}:</span>}
        <span className={selected ? "dropdown-value" : "dropdown-value placeholder"}>{selected?.label ?? placeholder}</span>
        <svg className="dropdown-chevron" viewBox="0 0 16 16" aria-hidden="true">
          <path d="M5 6.5l3-3 3 3M5 9.5l3 3 3-3" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open &&
        createPortal(
          <ul ref={menuRef} id={`${id}-menu`} role="listbox" className="dropdown-menu" style={position}>
            {options.map((option, index) => (
              <li
                key={option.value}
                id={`${id}-${index}`}
                role="option"
                aria-selected={option.value === value && !option.action}
                className={[
                  "dropdown-option",
                  index === active && "active",
                  option.value === value && !option.action && "selected",
                  option.action && "action",
                ]
                  .filter(Boolean)
                  .join(" ")}
                onMouseEnter={() => setActive(index)}
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => choose(option)}
              >
                {option.label}
              </li>
            ))}
          </ul>,
          document.body,
        )}
    </>
  );
}
