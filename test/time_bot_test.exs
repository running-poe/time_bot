defmodule TimeBotTest do
  use ExUnit.Case
  doctest TimeBot

  test "greets the world" do
    assert TimeBot.hello() == :world
  end
end
