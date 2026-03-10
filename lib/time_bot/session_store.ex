defmodule TimeBot.SessionStore do
  @moduledoc """
  Модуль для хранения состояния диалогов пользователей в оперативной памяти.
  Использует Agent для управления состоянием.
  Ключом является ID пользователя (Telegram Chat ID), значением — карта с данными текущего шага.
  """
  use Agent

  @doc """
  Запускает Agent с пустым начальным состоянием.
  """
  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Получает данные сессии для указанного пользователя.

  ## Параметры
    - `user_id`: ID пользователя Telegram.

  ## Возвращает
    - Структуру с данными сессии (например, `%{step: :waiting_for_name}`) или `nil`, если сессии нет.
  """
  def get(user_id) do
    Agent.get(__MODULE__, fn state -> Map.get(state, user_id) end)
  end

  @doc """
  Сохраняет или обновляет данные сессии пользователя.

  ## Параметры
    - `user_id`: ID пользователя Telegram.
    - `data`: Данные для сохранения (обычно карта с ключом `:step`).
  """
  def put(user_id, data) do
    Agent.update(__MODULE__, fn state -> Map.put(state, user_id, data) end)
  end

  @doc """
  Удаляет сессию пользователя (сбрасывает состояние диалога).

  ## Параметры
    - `user_id`: ID пользователя Telegram.
  """
  def delete(user_id) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, user_id) end)
  end
end
