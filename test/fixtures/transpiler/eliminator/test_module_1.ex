defmodule Hologram.Transpiler.Eliminator.TestModule1 do
  def not_action_1, do: nil

  def action(:test_1, a, b) do
    called_function()
  end

  def action(:test_2, a, b, c) do
    :ok
  end

  def action(:test_3, a, b) do
    :ok
  end

  def called_function, do: nil

  def not_action_2, do: nil
end
