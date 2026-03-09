defmodule TimeBot.CustomEvents do
  @moduledoc """
  Модуль для работы с пользовательскими событиями через Supabase.
  """

  require Logger

  # --- Публичные функции для бота ---

  @doc """
  Обрабатывает команду /add.
  Парсит строку и сохраняет событие в первый свободный слот.
  """
  def handle_add(user_id, text) do
    case parse_add_args(text) do
      {:ok, name, datetime} ->
        case find_free_slot(user_id) do
          {:ok, slot_id} ->
            case create_event(user_id, slot_id, name, datetime) do
              {:ok, _} -> "✅ Событие «#{name}» добавлено в слот ##{slot_id}."
              {:error, reason} -> "⚠️ Ошибка БД: #{inspect(reason)}"
            end
          :no_slots ->
            "❌ У вас уже 3 события. Удалите старые через /remove."
        end

      :error ->
        "❌ Неверный формат. Используйте:\n/add Название YYYY-MM-DD HH:MM\nили\n/add Название YYYY-MM-DD"
    end
  end

  @doc """
  Обрабатывает команду /events.
  Возвращает список событий пользователя.
  """
  def handle_list(user_id) do
    case get_events(user_id) do
      [] -> "У вас нет сохраненных событий."
      events ->
        msg = Enum.map(events, fn e ->
          dt_str = Timex.format!(e.event_date, "{YYYY}-{0M}-{0D} {h24}:{m}")
          "ID: #{e.slot_id} | #{e.event_name} — #{dt_str}"
        end) |> Enum.join("\n")
        "📅 Ваши события:\n#{msg}"
    end
  end

  @doc """
  Обрабатывает команду /remove.
  """
  def handle_remove(user_id, slot_str) do
    case Integer.parse(slot_str) do
      {slot_id, ""} when slot_id >= 0 and slot_id < 3 ->
        case delete_event(user_id, slot_id) do
          {:ok, _} -> "🗑 Событие ##{slot_id} удалено."
          {:error, _} -> "⚠️ Не удалось удалить (возможно, слот пуст)."
        end
      _ ->
        "❌ Укажите корректный ID (0, 1 или 2)."
    end
  end

  @doc """
  Обрабатывает команду /removeall.
  """
  def handle_remove_all(user_id) do
    case delete_all_events(user_id) do
      {:ok, _} -> "🗑 Все ваши события удалены."
      {:error, _} -> "⚠️ Ошибка при удалении."
    end
  end

  @doc """
  Возвращает список событий для Inline-режима.
  Формат: список структур для ответа Telegram.
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

  # --- Внутренняя логика и работа с Supabase ---

  defp parse_add_args(text) do
    # Пытаемся распарсить: /add Name YYYY-MM-DD HH:MM
    case String.split(text, " ", parts: 3) do
      [_, name, date_str] ->
        # Пробуем парсинг с временем
        case Timex.parse(date_str, "{YYYY}-{0M}-{0D} {h24}:{m}") do
          {:ok, dt} -> {:ok, name, Timex.to_datetime(dt)}
          {:error, _} ->
            # Пробуем парсинг без времени (ставим 00:00)
            case Timex.parse(date_str, "{YYYY}-{0M}-{0D}") do
              {:ok, dt} -> {:ok, name, Timex.to_datetime(dt)}
              _ -> :error
            end
        end
      _ -> :error
    end
  end

  defp find_free_slot(user_id) do
    events = get_events(user_id)
    used_slots = MapSet.new(events, & &1.slot_id)

    Enum.find_value(0..2, :no_slots, fn i ->
      if MapSet.member?(used_slots, i), do: nil, else: {:ok, i}
    end)
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

  # --- Supabase API Requests ---

  # Получение событий
  defp get_events(user_id) do
    url = supabase_url() <> "/rest/v1/time_bot_user_events_01?user_id=eq.#{user_id}&select=*"

    case request(:get, url) do
      {:ok, body} ->
        # ИСПОЛЬЗУЕМ JASON ВМЕСТО POISON
        Jason.decode!(body, keys: :atoms)
        |> Enum.map(fn e ->
          # Парсим строку даты из Supabase в Timex DateTime
          {:ok, dt, _} = DateTime.from_iso8601(e.event_date)
          %{e | event_date: Timex.to_datetime(dt)}
        end)
      _ -> []
    end
  end

  # Создание события (upsert)
  defp create_event(user_id, slot_id, name, datetime) do
    url = supabase_url() <> "/rest/v1/time_bot_user_events_01"
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

  # Удаление конкретного события
  defp delete_event(user_id, slot_id) do
    url = supabase_url() <> "/rest/v1/time_bot_user_events_01?user_id=eq.#{user_id}&slot_id=eq.#{slot_id}"
    request(:delete, url)
  end

  # Удаление всех событий
  defp delete_all_events(user_id) do
    url = supabase_url() <> "/rest/v1/time_bot_user_events_01?user_id=eq.#{user_id}"
    request(:delete, url)
  end

  # Базовый запрос
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
