import { normalize } from "./FilterBar";
import type { IconName } from "./Icon";

/** One thing the global search finds: a page, an object of a section or an action. */
export interface SearchItem {
  id: string;
  group: SearchGroup;
  title: string;
  subtitle?: string;
  /** More text to match: logins, cities, synonyms of a page. */
  keywords?: string;
  href: string;
  icon: IconName;
}

export type SearchGroup = "Действия" | "Разделы" | "Сотрудники" | "Руководители" | "Офисы" | "Департаменты" | "Награды";

/** Order of the groups in the results. */
export const GROUP_ORDER: SearchGroup[] = ["Сотрудники", "Руководители", "Офисы", "Департаменты", "Награды", "Разделы", "Действия"];

const MAX_PER_GROUP = 6;
const MAX_RESULTS = 40;

/** Higher is better; 0 = no match. Every word of the query must be found. */
function score(item: SearchItem, words: string[]): number {
  const title = normalize(item.title);
  const rest = normalize(`${item.subtitle ?? ""} ${item.keywords ?? ""}`);
  let total = 0;
  for (const word of words) {
    if (title.startsWith(word)) {
      total += 4;
    } else if (title.split(/\s+/).some((part) => part.startsWith(word))) {
      total += 3;
    } else if (title.includes(word)) {
      total += 2;
    } else if (rest.includes(word)) {
      total += 1;
    } else {
      return 0;
    }
  }
  return total;
}

/**
 * Best matches grouped by kind; the group with the best match goes first (an office found by its
 * name comes before the players of that office). An empty query shows the pages and the actions.
 */
export function searchItems(items: SearchItem[], query: string): { group: SearchGroup; items: SearchItem[] }[] {
  const words = normalize(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return GROUP_ORDER.map((group) => ({ group, items: items.filter((item) => item.group === group) })).filter(
      (section) => (section.group === "Разделы" || section.group === "Действия") && section.items.length > 0,
    );
  }
  const found = items
    .map((item) => ({ item, score: score(item, words) }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_RESULTS);
  const best = (group: SearchGroup) => Math.max(0, ...found.filter((entry) => entry.item.group === group).map((entry) => entry.score));
  return GROUP_ORDER.map((group) => ({
    group,
    best: best(group),
    items: found.filter((entry) => entry.item.group === group).slice(0, MAX_PER_GROUP).map((entry) => entry.item),
  }))
    .filter((section) => section.items.length > 0)
    .sort((a, b) => b.best - a.best)
    .map(({ group, items: groupItems }) => ({ group, items: groupItems }));
}
