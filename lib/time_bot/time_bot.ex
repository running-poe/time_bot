defmodule TimeBot.Bot do
  use GenServer
  require Logger

  # Конфигурация событий
  @events_config %{
    saturday: %{name: "субботы", emoji: "⏳", title: "Суббота"},
    spring: %{name: "весны", emoji: "🌷", title: "Весна"},
    summer: %{name: "лета", emoji: "☀️", title: "Лето"},
    newyear: %{name: "Нового года", emoji: "🎄", title: "Новый год"},
    evening: %{name: "19:00", emoji: "🌆", title: "19:00"}
  }

  # Клиентская часть
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Серверная часть
  @impl true
  def init(state) do
    Telegex.delete_webhook()
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    offset = Map.get(state, :offset, 0)

    case Telegex.get_updates(offset: offset, timeout: 30) do
      {:ok, updates} ->
        new_offset = process_updates(updates, offset)
        schedule_poll()
        {:noreply, Map.put(state, :offset, new_offset)}

      {:error, reason} ->
        Logger.error("Polling error: #{inspect(reason)}")
        schedule_poll()
        {:noreply, state}
    end
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, 100)

  # Обработка обновлений
  defp process_updates(updates, current_offset) do
    Enum.reduce(updates, current_offset, fn update, acc ->
      handle_update(update)
      max(acc, update.update_id + 1)
    end)
  end

  defp handle_update(%{inline_query: query}) when not is_nil(query), do: handle_inline(query)
  defp handle_update(%{message: msg}) when not is_nil(msg), do: handle_message(msg)
  defp handle_update(_), do: :ok

  # --- INLINE ЛОГИКА ---

  defp handle_inline(query) do
    results =
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
      |> Kernel.++([
        %Telegex.Type.InlineQueryResultArticle{
          id: "all",
          type: "article",
          title: "📊 Все события",
          input_message_content: %Telegex.Type.InputTextMessageContent{
            message_text: format_all_events()
          }
        }
      ])

    Telegex.answer_inline_query(query.id, results, cache_time: 30)
  end

  # --- ЛОГИКА СООБЩЕНИЙ ---

  defp handle_message(%{text: "/start"} = msg) do
    commands_list =
      @events_config
      |> Enum.map(fn {key, config} -> "/#{key} - до #{config.name}" end)
      |> Enum.join("\n")

    help_text = """
    🤖 Бот считает время до приятных событий

    Доступные команды:
    #{commands_list}
    /all - все события

    Или введите @имя_бота в любом чате!
    """
    Telegex.send_message(msg.chat.id, help_text)
  end

  defp handle_message(%{text: "/all"} = msg) do
    Telegex.send_message(msg.chat.id, format_all_events())
  end

  defp handle_message(%{text: "/" <> command} = msg) do
    key = String.to_atom(command)
    if Map.has_key?(@events_config, key) do
      Telegex.send_message(msg.chat.id, format_event_response(key))
    end
  end

  defp handle_message(%{text: text} = msg) do
    text_lower = String.downcase(text)

    keyword_to_event = %{
      "суббот" => :saturday,
      "весн" => :spring,
      "лет" => :summer,
      "новый год" => :newyear,
      "новогод" => :newyear,
      "19" => :evening,
      "вечер" => :evening,
      "семь" => :evening
    }

    response =
      Enum.find_value(keyword_to_event, "Используйте /start для списка команд", fn {keyword, key} ->
        if String.contains?(text_lower, keyword), do: format_event_response(key)
      end)

    response =
      if response == "Используйте /start для списка команд" and
           (String.contains?(text_lower, "все") or String.contains?(text_lower, "событи")) do
        format_all_events()
      else
        response
      end

    Telegex.send_message(msg.chat.id, response)
  end

  defp handle_message(_), do: :ok

  # --- ЛОГИКА РАСЧЕТА ВРЕМЕНИ ---

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

    # ВАЖНО: Обнуляем секунды и микросекунды в текущем времени
    # чтобы расчет велся "чисто" в минутах
    now =
      Timex.now(timezone)
      |> Timex.set(second: 0, microsecond: 0)

    target = case event_key do
      :saturday -> calculate_next_saturday(now)
      :spring   -> calculate_next_date(now, 3, 1)
      :summer   -> calculate_next_date(now, 6, 1)
      :newyear  -> calculate_next_date(now, 1, 1)
      :evening  -> calculate_next_19h(now)
    end

    calculate_time_remaining(target, now)
  end

  # Расчет: Суббота
  defp calculate_next_saturday(now) do
    # Timex weekday: 6 = Суббота
    days_to_add =
      cond do
        Timex.weekday(now) == 6 -> 7
        true -> 6 - Timex.weekday(now)
      end

    now
    |> Timex.shift(days: days_to_add)
    |> Timex.set(hour: 0, minute: 0, second: 0, microsecond: 0)
  end

  # Расчет: Сезоны
   defp calculate_next_date(now, month, day) do
    year = case {month, day} do
      {3, 1} -> if now.month >= 3, do: now.year + 1, else: now.year
      {6, 1} -> if now.month >= 6, do: now.year + 1, else: now.year
      {1, 1} -> now.year + 1 # Новый год всегда в следующем году (относительно текущего момента)
    end

    Timex.set(now, [year: year, month: month, day: day, hour: 0, minute: 0, second: 0, microsecond: 0])
  end

  # Расчет: 19:00
  defp calculate_next_19h(now) do
    target = Timex.set(now, [hour: 19, minute: 0, second: 0, microsecond: 0])
    if Timex.compare(target, now) == -1 do
      Timex.shift(target, days: 1)
    else
      target
    end
  end

  # Вывод только Дней, Часов и Минут
  defp calculate_time_remaining(target, now) do
    diff_sec = Timex.diff(target, now, :seconds)

    if diff_sec < 0 do
      "Время уже прошло"
    else
      days = div(diff_sec, 86400)
      hours = div(rem(diff_sec, 86400), 3600)
      minutes = div(rem(diff_sec, 3600), 60)
      "#{days}д #{hours}ч #{minutes}м"
    end
  end
end
