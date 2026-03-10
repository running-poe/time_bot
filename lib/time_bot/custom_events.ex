defmodule TimeBot.CustomEvents do
  @moduledoc """
  Модуль бизнес-логики для работы с пользовательскими событиями.
  Обеспечивает взаимодействие с Supabase, парсинг дат и форматирование ответов.
  """

  require Logger

  @table_name "time_bot_user_events_01"
  @max_slots 5

  # --- Публичные API функции ---

  @doc """
  Обрабатывает команду /add в "однострочном" режиме (если переданы аргументы).
  Парсит строку целиком, ищет название и дату.
  """
  def handle_add(user_id, text) do
    case parse_add_args(text) do
      {:ok, name, datetime} ->
        create_event_flow(user_id, name, datetime)

      :error ->
        "❌ Неверный формат. Используйте:\n/add Название YYYY-MM-DD HH:MM\nили\n/add Название YYYY-MM-DD"
    end
  end

  @doc """
  Основная функция создания события. Проверяет наличие свободных слотов,
  сохраняет в БД и возвращает сообщение с результатом и временем до события.
  Используется в конце пошагового диалога.
  """
  def create_event_flow(user_id, name, datetime) do
    case find_free_slot(user_id) do
      {:ok, slot_id} ->
        case create_event(user_id, slot_id, name, datetime) do
          {:ok, _} ->
            now = Timex.now(Application.get_env(:time_bot, :timezone, "Europe/Moscow"))
            time_str = calculate_time_remaining(datetime, now)
            "✅ Событие «#{name}» добавлено в слот ##{slot_id}.\n⏳ Осталось: #{time_str}"
          {:error, reason} -> "⚠️ Ошибка БД: #{inspect(reason)}"
        end
      :no_slots ->
        "❌ У вас уже #{@max_slots} событий. Удалите старые через /remove."
    end
  end

  @doc """
  Формирует список событий пользователя для вывода в чате.
  События сортируются по ID, для каждого рассчитывается оставшееся время.
  """
  def handle_list(user_id) do
    timezone = Application.get_env(:time_bot, :timezone, "Europe/Moscow")
    now = Timex.now(timezone)

    case get_events(user_id) do
      [] ->
        "У вас нет сохраненных событий."

      events ->
        sorted_events = Enum.sort_by(events, & &1.slot_id)

        msg = Enum.map(sorted_events, fn e ->
          dt_str = Timex.format!(e.event_date, "{YYYY}-{0M}-{0D} {h24}:{m}")
          time_str = calculate_time_remaining(e.event_date, now)
          "ID: #{e.slot_id} | #{e.event_name} — #{dt_str}\n⏳ Осталось: #{time_str}"
        end)
        |> Enum.join("\n\n")

        "📅 Ваши события:\n\n#{msg}"
    end
  end

  @doc """
  Удаляет событие по указанному ID (слоту).
  """
  def handle_remove(user_id, slot_str) do
    case Integer.parse(slot_str) do
      {slot_id, ""} when slot_id >= 0 and slot_id < @max_slots ->
        case delete_event(user_id, slot_id) do
          {:ok, _} -> "🗑 Событие ##{slot_id} удалено."
          {:error, _} -> "⚠️ Не удалось удалить (возможно, слот пуст)."
        end
      _ ->
        "❌ Укажите корректный ID (от 0 до #{@max_slots - 1})."
    end
  end

  @doc """
  Удаляет все события пользователя.
  """
  def handle_remove_all(user_id) do
    case delete_all_events(user_id) do
      {:ok, _} -> "🗑 Все ваши события удалены."
      {:error, _} -> "⚠️ Ошибка при удалении."
    end
  end

  @doc """
  Формирует список результатов для Inline-режима.
  Принимает `now` как аргумент для консистентности времени.
  """
  def get_inline_results(user_id, now) do
    events = get_events(user_id)

    Enum.map(events, fn e ->
      time_str = calculate_time_remaining(e.event_date, now)

      %Telegex.Type.InlineQueryResultArticle{
        id: "custom_#{e.slot_id}",
        type: "article",
        title: "🗓 #{e.event_name}: #{time_str}",
        input_message_content: %Telegex.Type.InputTextMessageContent{
          message_text: "🗓 До #{e.event_name}: #{time_str}"
        },
        description: "Ваше событие"
      }
    end)
  end

  @doc """
  Проверяет наличие свободных слотов для пользователя.
  Возвращает `{:ok, slot_id}` или `:no_slots`.
  Используется для валидации перед началом диалога.
  """
  def find_free_slot(user_id) do
    events = get_events(user_id)
    used_slots = MapSet.new(events, & &1.slot_id)

    Enum.find_value(0..(@max_slots - 1), :no_slots, fn i ->
      if MapSet.member?(used_slots, i), do: nil, else: {:ok, i}
    end)
  end

  @doc """
  Парсит строку с датой и временем. Используется на втором шаге диалога.
  Поддерживает форматы `YYYY-MM-DD HH:MM` и `YYYY-MM-DD`.
  Возвращает `{:ok, datetime}` или `:error`.
  """
  def parse_date(text) do
    timezone = Application.get_env(:time_bot, :timezone, "Europe/Moscow")

    case Timex.parse(String.trim(text), "{YYYY}-{0M}-{0D} {h24}:{m}") do
      {:ok, naive_dt} -> {:ok, Timex.to_datetime(naive_dt, timezone)}
      {:error, _} ->
        case Timex.parse(String.trim(text), "{YYYY}-{0M}-{0D}") do
          {:ok, naive_dt} -> {:ok, Timex.to_datetime(naive_dt, timezone)}
          _ -> :error
        end
    end
  end

  # --- Приватные функции ---

  defp parse_add_args(text) do
    regex = ~r/^(.*?)\s+(\d{4}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?)$/

    case Regex.run(regex, text) do
      [_, name, date_str] ->
        case parse_date(date_str) do
          {:ok, dt} -> {:ok, String.trim(name), dt}
          :error -> :error
        end
      _ ->
        :error
    end
  end

  defp calculate_time_remaining(target, now) do
    diff_sec = Timex.diff(target, now, :seconds)
    if diff_sec < 0, do: "Время прошло", else: format_diff(diff_sec)
  end

  defp format_diff(sec) do
    days = div(sec, 86400)
    hours = div(rem(sec, 86400), 3600)
    minutes = div(rem(sec, 3600), 60)
    "#{days}д #{hours}ч #{minutes}м"
  end

  # --- Supabase API ---

  defp get_events(user_id) do
    url = supabase_url() <> "/rest/v1/#{@table_name}?user_id=eq.#{user_id}&select=*"

    case request(:get, url) do
      {:ok, body} ->
        Jason.decode!(body, keys: :atoms)
        |> Enum.map(fn e ->
          {:ok, dt, _} = DateTime.from_iso8601(e.event_date)
          %{e | event_date: Timex.to_datetime(dt)}
        end)
      _ -> []
    end
  end

  defp create_event(user_id, slot_id, name, datetime) do
    url = supabase_url() <> "/rest/v1/#{@table_name}"
    body = Jason.encode!(%{
      user_id: user_id,
      slot_id: slot_id,
      event_name: name,
      event_date: datetime
    })

    headers = [
      {"Prefer", "resolution=merge-duplicates"},
      {"Content-Type", "application/json"}
    ]
    request(:post, url, body, headers)
  end

  defp delete_event(user_id, slot_id) do
    url = supabase_url() <> "/rest/v1/#{@table_name}?user_id=eq.#{user_id}&slot_id=eq.#{slot_id}"
    request(:delete, url)
  end

  defp delete_all_events(user_id) do
    url = supabase_url() <> "/rest/v1/#{@table_name}?user_id=eq.#{user_id}"
    request(:delete, url)
  end

  defp request(method, url, body \\ "", extra_headers \\ []) do
    headers = [
      {"apikey", supabase_key()},
      {"Authorization", "Bearer #{supabase_key()}"}
    ] ++ extra_headers

    case Finch.build(method, url, headers, body) |> Finch.request(TimeBot.Finch) do
      {:ok, %Finch.Response{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}
      {:ok, %Finch.Response{body: resp_body}} ->
        Logger.error("Supabase error: #{resp_body}")
        {:error, resp_body}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp supabase_url, do: Application.get_env(:time_bot, :supabase_url)
  defp supabase_key, do: Application.get_env(:time_bot, :supabase_key)
end
