import { Client, Session } from "@heroiclabs/nakama-js";

// Talks to the Nakama Go module (server/modules). Every call is an admin RPC checked on the server.

const env = import.meta.env;
// Opened over HTTPS (Caddy on the LAN) the panel may call only HTTPS: Nakama is proxied on 7443.
const pageIsHttps = window.location.protocol === "https:";
const client = new Client(
  env.VITE_NAKAMA_SERVER_KEY ?? "defaultkey",
  env.VITE_NAKAMA_HOST || window.location.hostname,
  env.VITE_NAKAMA_PORT ?? (pageIsHttps ? "7443" : "7350"),
  env.VITE_NAKAMA_SSL ? env.VITE_NAKAMA_SSL === "true" : pageIsHttps,
  10000,
  // Sessions last a week and are not refreshed: after that the admin signs in again.
  false,
);

const SESSION_KEY = "office-admin-session";

export interface Department {
  id: string;
  name: string;
}

export interface User {
  id: string;
  username: string;
  display_name: string;
  role: "admin" | "player" | "";
  department_id: string;
  banned: boolean;
  created_at: number;
}

export interface NewUser {
  username: string;
  password: string;
  display_name: string;
  department_id: string;
}

export interface PlayerSummary {
  id: string;
  username: string;
  display_name: string;
  department_id: string;
  banned: boolean;
  created_at: number;
  balance: number;
  streak: number;
  best_streak: number;
  office_days: number;
  excused_days: number;
  tasks_total: number;
  skipped_total: number;
  coins_earned: number;
  colleagues: number;
  /** Day numbers: days since 1970-01-01 in the office time zone; 0 = never played. */
  first_day: number;
  last_login_day: number;
  present_today: boolean;
  in_office: boolean;
  today: number;
  /** Unix seconds, 0 = no recorded actions. */
  last_activity: number;
  car: string;
  status: string;
  play_seconds_today: number;
  /** Continuous-play limit: ok, warning (must leave the game), resting or blocked until tomorrow. */
  play_state: PlayState;
}

export type PlayState = "ok" | "warning" | "resting" | "blocked";

/** Working-time limits (server/modules/limits.go); clocks are "HH:MM" office time. */
export interface Limits {
  task_cooldown_minutes: number;
  task_window_start: string;
  task_window_end: string;
  play_limit_minutes: number;
  exit_grace_minutes: number;
  rest_minutes: number;
}

export interface NamedId {
  id: string;
  name: string;
}

export interface TaskLogEntry {
  id: string;
  title: string;
  reward: number;
  /** Unix seconds; absent in records made before the time was stored. */
  t?: number;
}

export interface StatsDay {
  day: number;
  workday: boolean;
  present: boolean;
  excused: boolean;
  checkin_at: number;
  checkout_at: number;
  tasks: TaskLogEntry[];
  skipped: NamedId[];
  pending: NamedId[];
  met: string[];
  purchases: string[];
  earned: number;
  play_seconds: number;
}

export interface ActivityEvent {
  t: number;
  kind: string;
  params?: Record<string, unknown>;
}

export interface LedgerEntry {
  t: number;
  change: number;
  reason: string;
  ref: string;
}

export interface FlaggedEntry {
  t: number;
  task: string;
  reason: string;
}

export interface RewardRequest {
  t: number;
  item_id: string;
  price: number;
  status: string;
}

export interface PhotoRequest {
  id: string;
  day: number;
  task: string;
  partner: string;
  t: number;
  state: string;
  reward: number;
}

export interface PlayerStats {
  player: PlayerSummary;
  days: StatsDay[];
  activity: ActivityEvent[];
  ledger: LedgerEntry[];
  suspicious: FlaggedEntry[];
  reward_requests: RewardRequest[];
  photo_requests: PhotoRequest[];
  excused_days: number[];
  /** Display names of the task, item, car and user ids above. */
  names: Record<string, string>;
}

/** Error with a stable key from the server (see server/modules/errors.go) or a transport key. */
export class ApiError extends Error {
  constructor(readonly key: string) {
    super(key);
  }
}

async function toApiError(error: unknown): Promise<ApiError> {
  if (error instanceof Response) {
    if (error.status === 401) {
      return new ApiError("unauthenticated");
    }
    try {
      const body = (await error.json()) as { message?: string };
      return new ApiError(body.message ?? `http_${error.status}`);
    } catch {
      return new ApiError(`http_${error.status}`);
    }
  }
  return new ApiError("network");
}

async function call<T>(session: Session, id: string, payload: object = {}): Promise<T> {
  try {
    const response = await client.rpc(session, id, payload);
    return (response.payload ?? {}) as T;
  } catch (error) {
    throw await toApiError(error);
  }
}

export function restoreSession(): Session | null {
  try {
    const saved = JSON.parse(localStorage.getItem(SESSION_KEY) ?? "null") as { token: string; refresh: string } | null;
    if (!saved) {
      return null;
    }
    const session = Session.restore(saved.token, saved.refresh);
    return session.isexpired(Date.now() / 1000) ? null : session;
  } catch {
    return null;
  }
}

export async function signIn(username: string, password: string): Promise<Session> {
  let session: Session;
  try {
    session = await client.authenticateEmail("", password, false, username.trim().toLowerCase());
  } catch (error) {
    throw await toApiError(error);
  }
  // Only admin accounts may use the panel; the server says so on the first admin call.
  await call(session, "admin_list_users");
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify({ token: session.token, refresh: session.refresh_token }));
  } catch {
    // Private mode: the session lives until the tab closes.
  }
  return session;
}

export async function signOut(session: Session): Promise<void> {
  try {
    localStorage.removeItem(SESSION_KEY);
  } catch {
    // Nothing stored.
  }
  await client.sessionLogout(session, session.token, session.refresh_token).catch(() => undefined);
}

export const api = {
  listDepartments: (s: Session) => call<{ departments: Department[] }>(s, "list_departments").then((r) => r.departments),
  createDepartment: (s: Session, name: string) => call<Department>(s, "admin_create_department", { name }),
  renameDepartment: (s: Session, id: string, name: string) => call<Department>(s, "admin_rename_department", { id, name }),
  listUsers: (s: Session) => call<{ users: User[] }>(s, "admin_list_users").then((r) => r.users),
  createUser: (s: Session, user: NewUser) => call<User>(s, "admin_create_user", user),
  updateUser: (s: Session, user_id: string, changes: { display_name?: string; department_id?: string }) =>
    call(s, "admin_update_user", { user_id, ...changes }),
  setPassword: (s: Session, user_id: string, password: string) => call(s, "admin_set_password", { user_id, password }),
  setBanned: (s: Session, user_id: string, banned: boolean) => call(s, "admin_set_banned", { user_id, banned }),
  statsOverview: (s: Session) => call<{ players: PlayerSummary[] }>(s, "admin_stats_overview").then((r) => r.players),
  playerStats: (s: Session, user_id: string) => call<PlayerStats>(s, "admin_player_stats", { user_id }),
  getLimits: (s: Session) => call<{ limits: Limits; defaults: Limits }>(s, "admin_get_limits"),
  setLimits: (s: Session, limits: Limits) => call<Limits>(s, "admin_set_limits", limits),
};
