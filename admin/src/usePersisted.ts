import { useCallback, useState } from "react";

const PREFIX = "office-admin:";

function read<T>(key: string, initial: T): T {
  try {
    const saved = sessionStorage.getItem(PREFIX + key);
    return saved === null ? initial : { ...initial, ...(JSON.parse(saved) as T) };
  } catch {
    return initial;
  }
}

/**
 * Filter state of a list that survives opening an object and coming back (the browser tab session).
 * A convenience only: without storage the filters live until the page reloads.
 */
export function usePersisted<T extends object>(key: string, initial: T): [T, (next: T) => void] {
  const [value, setValue] = useState<T>(() => read(key, initial));
  const update = useCallback(
    (next: T) => {
      setValue(next);
      try {
        sessionStorage.setItem(PREFIX + key, JSON.stringify(next));
      } catch {
        // Private mode: keep the state in memory.
      }
    },
    [key],
  );
  return [value, update];
}
