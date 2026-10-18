import { useState, type FormEvent } from "react";
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
    <form className="card login" onSubmit={submit}>
      <h1>Вход в панель</h1>
      <p className="muted">Для администратора и руководителей.</p>
      <label>
        Логин
        <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" required />
      </label>
      <label>
        Пароль
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
      </label>
      {error && <p className="error">{error}</p>}
      <button type="submit" disabled={busy}>
        {busy ? "Вход…" : "Войти"}
      </button>
    </form>
  );
}
