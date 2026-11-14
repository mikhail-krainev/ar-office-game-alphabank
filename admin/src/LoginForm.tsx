import { useState, type FormEvent } from "react";
import { AlfaLogo } from "./AlfaLogo";
import { signIn, type PanelSession } from "./api";
import { errorText } from "./messages";

export function LoginForm({ onSignedIn }: { onSignedIn: (panel: PanelSession) => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      onSignedIn(await signIn(username, password));
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-page">
      <div className="login-brand">
        <span className="brand-mark large">
          <AlfaLogo size={36} />
        </span>
        <h1>
          Alfa<span className="brand-accent">Game</span>
        </h1>
        <p>Панель управления игрой: сотрудники, офисы, награды и статистика посещений.</p>
      </div>
      <form className="login-card" onSubmit={submit}>
        <h2>Вход в панель</h2>
        <p className="muted">Для администратора и руководителей. Аккаунт выдаёт администратор.</p>
        <label>
          Логин
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" autoCapitalize="none" required autoFocus />
        </label>
        <label>
          Пароль
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
        </label>
        {error && (
          <p className="error form-error" role="alert">
            {error}
          </p>
        )}
        <button type="submit" disabled={busy}>
          {busy ? "Вход…" : "Войти"}
        </button>
      </form>
    </div>
  );
}
