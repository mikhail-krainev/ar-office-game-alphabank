import { useState, type FormEvent } from "react";
import { useDialogs } from "./Dialogs";
import { generatePassword } from "./password";

export interface Issued {
  name: string;
  username: string;
  password: string;
}

/** Login and password to hand over, with a copy button; shown once after creating or resetting. */
export function IssuedCredentials({ issued, text, onDone }: { issued: Issued; text: string; onDone?: () => void }) {
  const { notify } = useDialogs();

  async function copy() {
    try {
      await navigator.clipboard.writeText(`логин: ${issued.username}\nпароль: ${issued.password}`);
      notify("Данные для входа скопированы.");
    } catch {
      notify("Не удалось скопировать: выделите текст вручную.", "error");
    }
  }

  return (
    <div className="issued">
      <p>
        {text} <b>{issued.name}</b>. Передайте данные для входа — пароль больше не будет показан:
      </p>
      <code>
        логин: {issued.username}
        <br />
        пароль: {issued.password}
      </code>
      <div className="form-actions">
        <button type="button" className="secondary" onClick={() => void copy()}>
          Скопировать
        </button>
        {onDone && (
          <button type="button" className="link" onClick={onDone}>
            Готово
          </button>
        )}
      </div>
    </div>
  );
}

/** Password field with a button that makes a new easy-to-dictate one. */
export function PasswordInput({ value, onChange }: { value: string; onChange: (value: string) => void }) {
  return (
    <span className="with-button">
      <input value={value} onChange={(e) => onChange(e.target.value)} minLength={8} required autoComplete="new-password" />
      <button type="button" className="secondary" title="Сгенерировать новый" onClick={() => onChange(generatePassword())}>
        ↻
      </button>
    </span>
  );
}

/** New password for an account; the old sessions end on the server. */
export function ResetPasswordForm({
  name,
  username,
  save,
  onDone,
}: {
  name: string;
  username: string;
  save: (password: string) => Promise<boolean>;
  onDone: () => void;
}) {
  const [password, setPassword] = useState(() => generatePassword());
  const [issued, setIssued] = useState<Issued | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (await save(password)) {
      setIssued({ name, username, password });
    }
  }

  if (issued) {
    return <IssuedCredentials issued={issued} text="Пароль изменён, старые сессии завершены:" onDone={onDone} />;
  }
  return (
    <form className="stack-form" onSubmit={submit}>
      <p className="muted">
        Логин <code>{username}</code>. После смены все открытые сессии этого аккаунта завершатся.
      </p>
      <label>
        Новый пароль (от 8 символов)
        <PasswordInput value={password} onChange={setPassword} />
      </label>
      <div className="form-actions">
        <button type="submit">Сменить пароль</button>
        <button type="button" className="secondary" onClick={onDone}>
          Отмена
        </button>
      </div>
    </form>
  );
}
