import { useCallback, useState } from "react";
import { restoreSession, signOut, type PanelSession } from "./api";
import { AdminPanel } from "./AdminPanel";
import { DialogsProvider } from "./Dialogs";
import { LoginForm } from "./LoginForm";
import { ManagerPanel } from "./ManagerPanel";

export function App() {
  const [panel, setPanel] = useState<PanelSession | null>(() => restoreSession());

  const handleSignOut = useCallback(() => {
    if (panel) {
      void signOut(panel.session);
    }
    setPanel(null);
    window.history.replaceState(null, "", "#/");
  }, [panel]);

  return (
    <DialogsProvider>
      <Panel panel={panel} onSessionLost={handleSignOut} onSignedIn={setPanel} />
    </DialogsProvider>
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
    return <ManagerPanel session={panel.session} onSessionLost={onSessionLost} />;
  }
  return <AdminPanel session={panel.session} onSessionLost={onSessionLost} />;
}
