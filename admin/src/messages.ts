import { ApiError } from "./api";

const MESSAGES: Record<string, string> = {
  unauthenticated: "Сессия истекла. Войдите снова.",
  network: "Сервер недоступен. Проверьте, что Nakama запущена.",
  not_admin: "Этот аккаунт не администратор.",
  "Invalid credentials.": "Неверный логин или пароль.",
  "User account not found.": "Неверный логин или пароль.",
  "User account banned.": "Аккаунт заблокирован.",
  invalid_username: "Логин: 3–32 символа, латиница в нижнем регистре, цифры, точка, _ или -.",
  invalid_password: "Пароль: от 8 символов (не больше 72 байт).",
  invalid_name: "Имя: от 1 до 60 символов.",
  username_taken: "Такой логин уже занят.",
  department_exists: "Департамент с таким названием уже есть.",
  department_not_found: "Выберите департамент из списка.",
  user_not_found: "Пользователь не найден.",
  admin_protected: "Аккаунт администратора меняется только через server/.env.",
  invalid_payload: "Сервер не понял запрос.",
  invalid_limits: "Проверьте значения: пауза 0–240 мин, предупреждение 5–480 мин, время на выход 1–60 мин, отдых 1–240 мин, начало раньше конца.",
};

export function errorText(error: unknown): string {
  if (error instanceof ApiError) {
    return MESSAGES[error.key] ?? `Ошибка: ${error.key}`;
  }
  return "Неизвестная ошибка.";
}

export function isSessionError(error: unknown): boolean {
  return error instanceof ApiError && (error.key === "unauthenticated" || error.key === "not_admin");
}
