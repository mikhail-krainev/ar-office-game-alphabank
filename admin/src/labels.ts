// Russian labels for the ids the server uses in statistics. Unknown ids are shown as they are.

export const ACTIVITY_LABELS: Record<string, string> = {
  login: "Вход в игру",
  check_in: "Вход в офис",
  check_out: "Выход из офиса",
  room: "Отметка в комнате",
  task_done: "Задание выполнено",
  task_pending: "Задание ждёт подтверждения",
  task_skipped: "Задание пропущено",
  met: "Встреча с коллегами",
  photo_answer: "Ответ на фото коллеги",
  play_warning: "Предупреждение о времени в игре",
  play_rest: "Ушёл на отдых",
  play_blocked: "Игра закрыта до завтра",
};

export const LEDGER_LABELS: Record<string, string> = {
  welcome_bonus: "Приветственный бонус",
  task_reward: "Награда за задание",
  photo_partner_bonus: "Бонус за фото с коллегой",
  absence_fine: "Штраф за пропуск",
  shop_purchase: "Покупка в магазине",
  car_purchase: "Покупка машины",
  raffle_ticket: "Билет розыгрыша",
  dev_grant: "Начисление (режим разработки)",
};

export const SUSPICIOUS_LABELS: Record<string, string> = {
  presence_token_invalid: "Недействительный QR-код офиса",
  presence_token_reused: "Повторное использование QR-кода",
  office_network_required: "Запрос не из сети офиса",
  duplicate_operation: "Повтор операции",
  colleague_invalid: "Неизвестный коллега",
  colleague_not_assigned: "Коллега не назначен",
  colleague_not_present: "Коллеги нет в офисе",
  colleague_other_office: "Коллега из другого офиса",
  colleague_already_used: "Коллега уже засчитан сегодня",
  not_enough_colleagues: "Мало коллег",
  not_enough_faces: "Мало лиц на фото",
  same_department: "Коллега из того же департамента",
  same_department_twice: "Два коллеги из одного департамента",
  photo_declined_by_partner: "Коллега не подтвердил фото",
  daily_cap_reached: "Дневной лимит монет",
};

/** Actions in the suspicious log that are not tasks. */
export const SUSPICIOUS_ACTIONS: Record<string, string> = {
  office_check_in: "Вход в офис",
  office_check_out: "Выход из офиса",
};

export const PLAY_STATES: Record<string, string> = {
  warning: "предупреждён",
  resting: "отдыхает",
  blocked: "закрыто до завтра",
};

export const ROOM_LABELS: Record<string, string> = {
  reception: "Ресепшн",
  kitchen: "Кухня",
  corridor: "Коридор",
  design: "Дизайн",
  lounge: "Лаунж",
  meeting: "Переговорная",
  open_space: "Опенспейс",
  pa_coffee: "Кофе-поинт",
  pa_open_space: "Опенспейс (ПА)",
  pa_workshop: "Мастерская (ПА)",
};

export const PHOTO_STATES: Record<string, string> = {
  pending: "ждёт ответа",
  confirmed: "подтверждено",
  declined: "отклонено",
  expired: "истекло",
};

export const REWARD_STATES: Record<string, string> = {
  pending: "ждёт подтверждения",
  approved: "выдано",
  rejected: "отклонено",
};

export function label(labels: Record<string, string>, id: string): string {
  return labels[id] ?? id;
}

/** Suspicious reasons may carry a suffix: "photo_declined_by_partner:<user id>". */
export function suspiciousLabel(reason: string): string {
  const [key] = reason.split(":");
  return SUSPICIOUS_LABELS[key] ?? reason;
}
