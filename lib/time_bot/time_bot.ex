defmodule TimeBot.Bot do
  use GenServer
  require Logger

  @moduledoc """
  Основной модуль Telegram бота.
  Реализует GenServer для обработки Long Polling обновлений от Telegram.
  Содержит логику меню команд, базовых событий и пошаговых диалогов.
  """

  @events_config %{
    saturday: %{name: "субботы", emoji: "⏳", title: "Суббота"},
    spring: %{name: "весны", emoji: "🌷", title: "Весна"},
    summer: %{name: "лета", emoji: "☀️", title: "Лето"},
    newyear: %{name: "Нового года", emoji: "🎄", title: "Новый год"},
    evening: %{name: "19:00", emoji: "🌆", title: "19:00"}
  }

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("Bot is starting...")
    Telegex.delete_webhook()
    setup_bot_commands()
    schedule_poll()
    {:ok, state}
  end

  defp setup_bot_commands do
    commands = [
      %Telegex.Type.BotCommand{command: "start", description: "Начало работы"},
      %Telegex.Type.BotCommand{command: "add", description: "Добавить событие"},
      %Telegex.Type.BotCommand{command: "events", description: "Мои события"},
      %Telegex.Type.BotCommand{command: "remove", description: "Удалить событие"},
      %Telegex.Type.BotCommand{command: "removeall", description: "Удалить все события"},
      %Telegex.Type.BotCommand{command: "cancel", description: "Отменить текущее действие"},
      # Остальные команды...
      %Telegex.Type.BotCommand{command: "all", description: "Все базовые события"}
    ]
    Telegex.set_my_commands(commands)
  end

  @impl true
  def handle_info(:poll, state) do
    offset = Map.get(state, :offset, 0)

    case Telegex.get_updates(offset: offset, timeout: 10) do
      {:ok, updates} ->
        new_offset = process_updates(updates, offset)
        schedule_poll()
        {:noreply, Map.put(state, :offset, new_offset)}

      {:error, reason} ->
        Logger.warning("Polling error: #{inspect(reason)}")
        schedule_poll()
        {:noreply, state}
    end
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, 100)

  defp process_updates(updates, current_offset) do
    Enum.reduce(updates, current_offset, fn update, acc ->
      handle_update(update)
      max(acc, update.update_id + 1)
    end)
  end

  defp handle_update(%{inline_query: query}) when not is_nil(query), do: handle_inline(query)
  defp handle_update(%{message: msg}) when not is_nil(msg), do: handle_message(msg)
  defp handle_update(_), do: :ok

  # --- INLINE ---

  defp handle_inline(query) do
    now = Timex.now(Application.get_env(:time_bot, :timezone, "Europe/Moscow"))

    base_results =
      @events_config
      |> Enum.map(fn {key, config} ->
        time_str = get_event_time(key)
        %Telegex.Type.InlineQueryResultArticle{
          id: Atom.to_string(key),
          type: "article",
          title: "#{config.emoji} #{config.title}: #{time_str}",
          input_message_content: %Telegex.Type.InputTextMessageContent{
            message_text: format_event_response(key)
          }
        }
      end)

    custom_results = TimeBot.CustomEvents.get_inline_results(query.from.id, now)
    all_event_item = %Telegex.Type.InlineQueryResultArticle{
      id: "all",
      type: "article",
      title: "📊 Все события",
      input_message_content: %Telegex.Type.InputTextMessageContent{
        message_text: format_all_events()
      }
    }

    results = base_results ++ custom_results ++ [all_event_item]
    Telegex.answer_inline_query(query.id, results, cache_time: 0)
  end

  # --- ОБРАБОТКА СООБЩЕНИЙ И ДИАЛОГОВ ---

  defp handle_message(%{text: text} = msg) when is_binary(text) do
    user_id = msg.from.id
    session = TimeBot.SessionStore.get(user_id)

    # Если есть активная сессия, обрабатываем шаги диалога
    if session do
      handle_session(msg, session)
    else
      # Если сессии нет, обрабатываем обычные команды
      handle_normal_commands(msg)
    end
  end

  defp handle_message(_), do: :ok

   # --- Логика диалога (State Machine) ---

  # 1. Самый приоритетный вариант: Отмена диалога
  # Если текст равен "/cancel", срабатывает эта функция, независимо от шага
    defp handle_session(msg, session) do
    # Используем cond для строгого порядка проверки
    cond do
      # 1. Самый приоритетный сценарий: Команда отмены
      msg.text == "/cancel" ->
        TimeBot.SessionStore.delete(msg.from.id)
        Telegex.send_message(msg.chat.id, "🚫 Действие отменено.")

      # 2. Если это не отмена, проверяем шаги
      session.step == :waiting_for_name ->
        handle_waiting_for_name(msg)

      session.step == :waiting_for_date ->
        handle_waiting_for_date(msg, session.name)

      # На случай непредвиденных состояний
      true ->
        TimeBot.SessionStore.delete(msg.from.id)
        Telegex.send_message(msg.chat.id, "Произошла ошибка состояния. Начните заново.")
    end
  end

  # Обработка ввода названия
  defp handle_waiting_for_name(msg) do
    name = String.trim(msg.text)

    cond do
      # Защита: название не может быть командой
      String.starts_with?(name, "/") ->
        Telegex.send_message(msg.chat.id, "❌ Название не может начинаться с /. Введите название:")

      # Проверка длины
      String.length(name) < 1 or String.length(name) > 50 ->
        Telegex.send_message(msg.chat.id, "❌ Название должно быть от 1 до 50 символов. Попробуйте еще раз:")

      # Успех: сохраняем и идем дальше
      true ->
        TimeBot.SessionStore.put(msg.from.id, %{step: :waiting_for_date, name: name})
        Telegex.send_message(msg.chat.id, "📅 Отлично! Теперь укажите дату и время события в формате:\n`YYYY-MM-DD HH:MM`\n\n(Время можно не указывать, будет 00:00)\nДля отмены введите /cancel", parse_mode: "Markdown")
    end
  end

  # Обработка ввода даты
  defp handle_waiting_for_date(msg, name) do
    case TimeBot.CustomEvents.parse_date(msg.text) do
      {:ok, datetime} ->
        response = TimeBot.CustomEvents.create_event_flow(msg.from.id, name, datetime)
        TimeBot.SessionStore.delete(msg.from.id)
        Telegex.send_message(msg.chat.id, response)

      :error ->
        Telegex.send_message(msg.chat.id, "❌ Неверный формат даты. Попробуйте еще раз или введите /cancel для отмены:")
    end
  end

  # Обработка обычных команд (без диалога)
  defp handle_normal_commands(msg) do
    text = msg.text
    cond do
      text == "/start" -> send_help(msg.chat.id)
      text == "/cancel" -> Telegex.send_message(msg.chat.id, "Нет активного действия для отмены.")

      # НАЧАЛО ДИАЛОГА
      # ИЗМЕНЕНО: Проверяем наличие места ДО начала диалога
      text == "/add" ->
        case TimeBot.CustomEvents.find_free_slot(msg.from.id) do
          :no_slots ->
            Telegex.send_message(msg.chat.id, "❌ У вас уже 5 событий. Удалите старые через /remove.")
          {:ok, _slot_id} ->
            # Место есть, начинаем диалог
            TimeBot.SessionStore.put(msg.from.id, %{step: :waiting_for_name})
            Telegex.send_message(msg.chat.id, "➕ Добавление нового события.\n\nВведите название события:")
        end

      text == "/events" ->
        response = TimeBot.CustomEvents.handle_list(msg.from.id)
        Telegex.send_message(msg.chat.id, response)

        # ИЗМЕНЕНО: Обработка /remove без параметров
      String.starts_with?(text, "/remove") ->
        args = String.slice(text, 7..-1//1) |> String.trim()

        if args == "" do
          # Если аргументов нет, показываем список и инструкцию
          case TimeBot.CustomEvents.handle_list(msg.from.id) do
            "У вас нет сохраненных событий." ->
              Telegex.send_message(msg.chat.id, "У вас нет сохраненных событий для удаления.")
            events_list ->
              help_msg = events_list <> "\n\n💡 Укажите ID события для удаления.\nПример: /remove 0"
              Telegex.send_message(msg.chat.id, help_msg)
          end
        else
          # Если аргумент есть, пытаемся удалить
          response = TimeBot.CustomEvents.handle_remove(msg.from.id, args)
          Telegex.send_message(msg.chat.id, response)
        end

      text == "/removeall" ->
        response = TimeBot.CustomEvents.handle_remove_all(msg.from.id)
        Telegex.send_message(msg.chat.id, response)

      text == "/all" ->
        Telegex.send_message(msg.chat.id, format_all_events())

      true ->
        handle_generic_text(msg)
    end
  end

  # ... Вспомогательные функции (send_help, handle_generic_text, расчет времени и т.д.) остаются без изменений ...

  defp send_help(chat_id) do
    help_text = """
    🤖 Бот считает время до приятных событий

    📅 Базовые события:
    /saturday - до субботы
    /spring - до весны
    /summer - до лета
    /newyear - до Нового года
    /evening - до 19:00
    /all - показать все базовые события

    🗒 Ваши события:
    /events - список ваших сохраненных событий
    /add - добавить событие (пошаговый диалог)

    /remove ID - удалить событие по номеру
    /removeall - удалить все ваши события

    💡 Или введите @имя_бота в любом чате!
    """
    Telegex.send_message(chat_id, help_text)
  end

  defp handle_generic_text(msg) do
    text = msg.text
    key = text |> String.trim("/") |> String.to_atom()

    if Map.has_key?(@events_config, key) do
      Telegex.send_message(msg.chat.id, format_event_response(key))
    else
      handle_keywords(msg)
    end
  end

  defp handle_keywords(msg) do
    text_lower = String.downcase(msg.text)
    keyword_to_event = %{
      "суббот" => :saturday, "весн" => :spring, "лет" => :summer,
      "новый год" => :newyear, "новогод" => :newyear,
      "19" => :evening, "вечер" => :evening, "семь" => :evening
    }

    response = Enum.find_value(keyword_to_event, "Используйте /start для списка команд", fn {keyword, key} ->
      if String.contains?(text_lower, keyword), do: format_event_response(key)
    end)

    response = if response == "Используйте /start для списка команд" and
       (String.contains?(text_lower, "все") or String.contains?(text_lower, "событи")) do
      format_all_events()
    else
      response
    end

    Telegex.send_message(msg.chat.id, response)
  end

  # --- Расчет времени (без изменений) ---

  defp format_event_response(event_key) do
    config = @events_config[event_key]
    time_str = get_event_time(event_key)
    "#{config.emoji} До #{config.name}: #{time_str}"
  end

  defp format_all_events do
    @events_config
    |> Enum.map(fn {key, _} -> format_event_response(key) end)
    |> Enum.join("\n")
  end

  defp get_event_time(event_key) do
    timezone = Application.get_env(:time_bot, :timezone, "Europe/Moscow")
    now = Timex.now(timezone) |> Timex.set(second: 0, microsecond: 0)

    target = case event_key do
      :saturday -> calculate_next_saturday(now)
      :spring   -> calculate_next_date(now, 3, 1)
      :summer   -> calculate_next_date(now, 6, 1)
      :newyear  -> calculate_next_date(now, 1, 1)
      :evening  -> calculate_next_19h(now)
    end
    calculate_time_remaining(target, now)
  end

  defp calculate_next_saturday(now) do
    days_to_add = if Timex.weekday(now) == 6, do: 7, else: 6 - Timex.weekday(now)
    now |> Timex.shift(days: days_to_add) |> Timex.set(hour: 0, minute: 0, second: 0, microsecond: 0)
  end

  defp calculate_next_date(now, month, day) do
    year = case {month, day} do
      {3, 1} -> if now.month >= 3, do: now.year + 1, else: now.year
      {6, 1} -> if now.month >= 6, do: now.year + 1, else: now.year
      {1, 1} -> now.year + 1
    end
    Timex.set(now, [year: year, month: month, day: day, hour: 0, minute: 0, second: 0, microsecond: 0])
  end

  defp calculate_next_19h(now) do
    target = Timex.set(now, [hour: 19, minute: 0, second: 0, microsecond: 0])
    if Timex.compare(target, now) == :lt, do: Timex.shift(target, days: 1), else: target
  end

  defp calculate_time_remaining(target, now) do
    diff_sec = Timex.diff(target, now, :seconds)
    if diff_sec < 0, do: "Время уже прошло", else: "#{div(diff_sec, 86400)}д #{div(rem(diff_sec, 86400), 3600)}ч #{div(rem(diff_sec, 3600), 60)}м"
  end
end
