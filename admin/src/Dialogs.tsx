import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { Icon } from "./Icon";

// Confirmations and notifications of the whole panel, in place of window.confirm and window.alert.

export interface ConfirmOptions {
  title: string;
  text: ReactNode;
  confirmLabel: string;
  /** Destructive action: the button is red and the cancel button gets the focus. */
  danger?: boolean;
}

type ToastKind = "success" | "error";

interface Toast {
  id: number;
  kind: ToastKind;
  text: string;
}

interface Dialogs {
  confirm: (options: ConfirmOptions) => Promise<boolean>;
  notify: (text: string, kind?: ToastKind) => void;
}

const SUCCESS_TOAST_MS = 4000;

const DialogsContext = createContext<Dialogs | null>(null);

export function useDialogs(): Dialogs {
  const dialogs = useContext(DialogsContext);
  if (!dialogs) {
    throw new Error("useDialogs outside DialogsProvider");
  }
  return dialogs;
}

export function DialogsProvider({ children }: { children: ReactNode }) {
  const [pending, setPending] = useState<{ options: ConfirmOptions; resolve: (ok: boolean) => void } | null>(null);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const nextId = useRef(0);

  const confirm = useCallback(
    (options: ConfirmOptions) => new Promise<boolean>((resolve) => setPending({ options, resolve })),
    [],
  );

  const dismiss = useCallback((id: number) => setToasts((current) => current.filter((toast) => toast.id !== id)), []);

  const notify = useCallback(
    (text: string, kind: ToastKind = "success") => {
      const id = nextId.current++;
      // An error stays until it is closed: the admin has to read it.
      setToasts((current) => [...current.filter((toast) => toast.text !== text), { id, kind, text }]);
      if (kind === "success") {
        window.setTimeout(() => dismiss(id), SUCCESS_TOAST_MS);
      }
    },
    [dismiss],
  );

  const answer = useCallback(
    (ok: boolean) => {
      pending?.resolve(ok);
      setPending(null);
    },
    [pending],
  );

  return (
    <DialogsContext.Provider value={{ confirm, notify }}>
      {children}
      {pending && <ConfirmDialog options={pending.options} onAnswer={answer} />}
      <div className="toasts" role="status" aria-live="polite">
        {toasts.map((toast) => (
          <div key={toast.id} className={`toast ${toast.kind}`}>
            <span>{toast.text}</span>
            <button type="button" className="icon-button" aria-label="Закрыть" onClick={() => dismiss(toast.id)}>
              <Icon name="x" size={16} />
            </button>
          </div>
        ))}
      </div>
    </DialogsContext.Provider>
  );
}

function ConfirmDialog({ options, onAnswer }: { options: ConfirmOptions; onAnswer: (ok: boolean) => void }) {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    (options.danger ? cancelRef : confirmRef).current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onAnswer(false);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [options, onAnswer]);

  return (
    <div className="overlay" onMouseDown={() => onAnswer(false)}>
      <div className="modal" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title" onMouseDown={(e) => e.stopPropagation()}>
        <h2 id="confirm-title">{options.title}</h2>
        <div className="modal-text">{options.text}</div>
        <div className="modal-actions">
          <button ref={cancelRef} type="button" className="secondary" onClick={() => onAnswer(false)}>
            Отмена
          </button>
          <button ref={confirmRef} type="button" className={options.danger ? "danger-solid" : ""} onClick={() => onAnswer(true)}>
            {options.confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
