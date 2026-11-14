import { useSyncExternalStore } from "react";

// Hash routes ("#/players/<id>?tab=coins"): every page and object of the panel has its own address,
// so the global search, the back button and a copied link all open the same place.

export interface Route {
  /** Path parts: "#/offices/hq" -> ["offices", "hq"]; the home page is []. */
  parts: string[];
  query: URLSearchParams;
}

function currentHash(): string {
  return window.location.hash;
}

function subscribe(onChange: () => void): () => void {
  window.addEventListener("hashchange", onChange);
  return () => window.removeEventListener("hashchange", onChange);
}

export function parseRoute(hash: string): Route {
  const [path, search = ""] = hash.replace(/^#\/?/, "").split("?");
  return {
    parts: path.split("/").filter(Boolean).map(decodeURIComponent),
    query: new URLSearchParams(search),
  };
}

export function useRoute(): Route {
  const hash = useSyncExternalStore(subscribe, currentHash);
  return parseRoute(hash);
}

/** "#/players/abc?tab=coins" from parts and query values; empty query values are left out. */
export function href(parts: string[], query: Record<string, string> = {}): string {
  const path = parts.map(encodeURIComponent).join("/");
  const search = new URLSearchParams(Object.entries(query).filter(([, value]) => value !== "")).toString();
  return `#/${path}${search ? `?${search}` : ""}`;
}

export function navigate(to: string): void {
  if (window.location.hash !== to) {
    window.location.hash = to;
  }
  window.scrollTo({ top: 0 });
}
