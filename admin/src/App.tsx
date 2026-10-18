import { useCallback, useState } from "react";
import { restoreSession, signOut, type PanelSession } from "./api";
import { LoginForm } from "./LoginForm";
import { Dashboard } from "./Dashboard";
import { ManagerDashboard } from "./ManagerDashboard";
import { AlfaLogo } from "./AlfaLogo";

export function App() {
  const [panel, setPanel] = useState<PanelSession | null>(() => restoreSession());

  const handleSignOut = useCallback(() => {
    if (panel) {
      void signOut(panel.session);
    }
    setPanel(null);
  }, [panel]);

  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <span className="brand">
            <AlfaLogo />
            <span>
              Alfa<span className="brand-accent">Game</span>
            </span>
            <span className="brand-sub">{panel?.role === "manager" ? "панель руководителя" : "админка"}</span>
          </span>
          {panel && (
            <button className="link" onClick={handleSignOut}>
              Выйти
            </button>
          )}
        </div>
      </header>
      <main className="app">
        <Panel panel={panel} onSessionLost={handleSignOut} onSignedIn={setPanel} />
      </main>
    </>
  );
}

/** The admin and a manager get two different panels; the server checks the role of every call too. */
function Panel({
  panel,
  onSessionLost,
  onSignedIn,
}: {
  panel: PanelSession | null;
  onSessionLost: () => void;
  onSignedIn: (panel: PanelSession) => void;
}) {
  if (!panel) {
    return <LoginForm onSignedIn={onSignedIn} />;
  }
  if (panel.role === "manager") {
    return <ManagerDashboard session={panel.session} onSessionLost={onSessionLost} />;
  }
  return <Dashboard session={panel.session} onSessionLost={onSessionLost} />;
}
