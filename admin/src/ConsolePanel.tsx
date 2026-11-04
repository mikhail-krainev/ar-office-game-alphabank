import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { api, ApiError, type ConsoleCommand, type ConsoleInfo } from "./api";
import type { DashboardActions } from "./Dashboard";
import { errorText, isSessionError } from "./messages";

const HISTORY_KEY = "office-admin-console-history";
const MAX_HISTORY = 100;
const MAX_LINES = 500;
const MAX_SUGGESTIONS = 8;
/** Handled by the panel itself, not sent to the server. */
const CLEAR_COMMANDS = ["clear", "cls"];

type LineKind = "input" | "output" | "error" | "info";

interface Line {
  id: number;
  kind: LineKind;
  text: string;
}

function loadHistory(): string[] {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(HISTORY_KEY) ?? "[]");
    return Array.isArray(saved) ? saved.filter((item): item is string => typeof item === "string") : [];
  } catch {
    return [];
  }
}

function saveHistory(history: string[]) {
  try {
    localStorage.setItem(HISTORY_KEY, JSON.stringify(history.slice(-MAX_HISTORY)));
  } catch {
    // The history is a convenience: without storage it lives until the page reloads.
  }
}

/** The longest common start of the names, for Tab completion. */
function commonPrefix(names: string[]): string {
  return names.reduce((prefix, name) => {
    let i = 0;
    while (i < prefix.length && prefix[i] === name[i]) {
      i++;
    }
    return prefix.slice(0, i);
  });
}

/**
 * Developer console of the game, like the console of a Source game: the server parses and runs each
 * command line (server/modules/console.go). With APP_ENV=prod only the commands that show data run.
 */
export function ConsolePanel({ actions }: { actions: DashboardActions }) {
  const { session, report } = actions;
  const [info, setInfo] = useState<ConsoleInfo | null>(null);
  const [lines, setLines] = useState<Line[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [history, setHistory] = useState(loadHistory);
  const [historyIndex, setHistoryIndex] = useState(-1);
  const nextId = useRef(0);
  const outputRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const print = (kind: LineKind, text: string) =>
    setLines((current) => [...current, { id: nextId.current++, kind, text }].slice(-MAX_LINES));

  useEffect(() => {
    api.consoleInfo(session).then(
      (loaded) => {
        setInfo(loaded);
        const mode = loaded.env === "dev" ? "dev: доступны все команды" : "prod: только просмотр данных";
        // Replaces the log, so a repeated effect (React strict mode) does not greet twice.
        setLines([{ id: nextId.current++, kind: "info", text: `Консоль игры. Окружение ${mode}. help — список команд, Tab — дополнение, ↑/↓ — история.` }]);
      },
      (e: unknown) => report(e),
    );
  }, [session, report]);

  useEffect(() => {
    outputRef.current?.scrollTo({ top: outputRef.current.scrollHeight });
  }, [lines]);

  const commands = (info?.commands ?? []).filter((command) => !command.dev || info?.env === "dev");
  const firstWord = input.trimStart().split(/\s+/)[0].toLowerCase();
  const typingName = firstWord !== "" && !/\s/.test(input.trimStart());
  const suggestions: ConsoleCommand[] = firstWord
    ? commands.filter((command) => (typingName ? command.name.startsWith(firstWord) : command.name === firstWord)).slice(0, MAX_SUGGESTIONS)
    : [];

  const remember = (line: string) => {
    const next = [...history.filter((item) => item !== line), line].slice(-MAX_HISTORY);
    setHistory(next);
    saveHistory(next);
    setHistoryIndex(-1);
  };

  const execute = async (line: string) => {
    print("input", line);
    remember(line);
    if (CLEAR_COMMANDS.includes(line.toLowerCase())) {
      setLines([]);
      return;
    }
    setBusy(true);
    try {
      const result = await api.consoleRun(session, line);
      if (result.error) {
        print("error", errorText(new ApiError(result.error)));
      } else {
        print(result.ok ? "output" : "error", result.output);
      }
    } catch (e) {
      if (isSessionError(e)) {
        report(e);
      } else {
        print("error", errorText(e));
      }
    } finally {
      setBusy(false);
      inputRef.current?.focus();
    }
  };

  const browseHistory = (step: number) => {
    if (!history.length) {
      return;
    }
    const start = historyIndex === -1 ? history.length : historyIndex;
    const index = start + step;
    if (index >= history.length) {
      setHistoryIndex(-1);
      setInput("");
      return;
    }
    const clamped = Math.max(0, index);
    setHistoryIndex(clamped);
    setInput(history[clamped]);
  };

  const complete = () => {
    if (!typingName || !suggestions.length) {
      return;
    }
    const names = suggestions.map((command) => command.name);
    const prefix = names.length === 1 ? `${names[0]} ` : commonPrefix(names);
    if (prefix.length > firstWord.length) {
      setInput(prefix);
    }
  };

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") {
      event.preventDefault();
      const line = input.trim();
      if (line && !busy) {
        setInput("");
        void execute(line);
      }
    } else if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      event.preventDefault();
      browseHistory(event.key === "ArrowUp" ? -1 : 1);
    } else if (event.key === "Tab") {
      event.preventDefault();
      complete();
    } else if (event.key === "l" && event.ctrlKey) {
      event.preventDefault();
      setLines([]);
    }
  };

  return (
    <div className="card console-card">
      <div className="section-head">
        <h2>Консоль</h2>
        {info && <span className={info.env === "dev" ? "badge present" : "badge soft"}>{info.env === "dev" ? "DEV: все команды" : "PROD: только просмотр"}</span>}
      </div>
      <div className="console" onClick={() => inputRef.current?.focus()}>
        <div className="console-output" ref={outputRef} role="log" aria-live="polite">
          {lines.map((line) => (
            <pre key={line.id} className={`console-line ${line.kind}`}>
              {line.kind === "input" ? `] ${line.text}` : line.text}
            </pre>
          ))}
          {busy && <pre className="console-line info">…</pre>}
        </div>
        <div className="console-input">
          <span aria-hidden="true">]</span>
          <input
            ref={inputRef}
            value={input}
            onChange={(event) => {
              setInput(event.target.value);
              setHistoryIndex(-1);
            }}
            onKeyDown={onKeyDown}
            spellCheck={false}
            autoComplete="off"
            autoCapitalize="off"
            autoFocus
            aria-label="Команда консоли"
            placeholder="help"
          />
        </div>
      </div>
      {suggestions.length > 0 && (
        <ul className="console-suggestions">
          {suggestions.map((command) => (
            <li key={command.name}>
              <code>
                {command.name} {command.args}
              </code>
              <span className="muted">{command.help}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
