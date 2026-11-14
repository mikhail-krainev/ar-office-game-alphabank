import type { PlayerSummary } from "./api";
import { PLAY_STATES } from "./labels";

/** Presence of a player now; also the values of the "Статус" filter. */
export type Presence = "on_site" | "went_out" | "was_today" | "absent" | "never" | "banned";

export const PRESENCE_LABELS: Record<Presence, string> = {
  on_site: "в офисе",
  went_out: "вышел",
  was_today: "был сегодня",
  absent: "не в офисе",
  never: "не начинал",
  banned: "заблокирован",
};

export function presenceOf(player: PlayerSummary): Presence {
  if (player.banned) {
    return "banned";
  }
  if (player.on_site) {
    return "on_site";
  }
  if (player.in_office) {
    return "went_out";
  }
  if (player.present_today) {
    return "was_today";
  }
  return player.first_day ? "absent" : "never";
}

const PRESENCE_CLASS: Record<Presence, string> = {
  on_site: "badge present",
  went_out: "badge soft",
  was_today: "badge soft",
  absent: "badge muted-badge",
  never: "badge muted-badge",
  banned: "badge missed",
};

export function PresenceBadge({ player }: { player: PlayerSummary }) {
  const presence = presenceOf(player);
  return (
    <span className={PRESENCE_CLASS[presence]}>
      {presence === "on_site" && <span className="dot" aria-hidden="true" />}
      {PRESENCE_LABELS[presence]}
    </span>
  );
}

/** Continuous-play limit state; nothing while the player plays within the limit. */
export function PlayBadge({ player }: { player: PlayerSummary }) {
  if (player.banned || player.play_state === "ok" || !player.play_state) {
    return null;
  }
  return <span className={player.play_state === "warning" ? "badge soft" : "badge missed"}>{PLAY_STATES[player.play_state]}</span>;
}
