import type { Session } from "@heroiclabs/nakama-js";
import type { Department, Office, PanelRole, PlayerStats, PlayerSummary } from "./api";

/** What every page of a panel gets: the loaded lists and the way to call the server. */
export interface DashboardActions {
  session: Session;
  role: PanelRole;
  offices: Office[];
  departments: Department[];
  /** Players this panel may see (all for the admin, the scope for a manager); null while loading. */
  players: PlayerSummary[] | null;
  officeName: (id: string) => string;
  departmentName: (id: string) => string;
  /** Runs a server call, reloads the lists afterwards and reports errors. Resolves to false on error. */
  run: (action: () => Promise<unknown>) => Promise<boolean>;
  /** Reloads the lists without a call. */
  reload: () => Promise<void>;
  /** Null in the manager panel: only the admin creates departments. */
  createDepartment: ((name: string, officeId: string) => Promise<Department | null>) | null;
  loadPlayerStats: (userId: string) => Promise<PlayerStats>;
  /** Shows an error of a call made outside `run`, or signs out when the session is gone. */
  report: (error: unknown) => void;
}
