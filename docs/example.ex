defmodule Somepage do
  def state do
    %{
      a: 1,
      b: 2
    }
  end

  def action(:update_value_a, "5", state) do
    assign(state, :a, 5)
  end

  def action(:update_value_a, value, state) do
    assign(state, :a, value)
  end

  def command(:save_record, value) do
    Repo.update(...)
    :ok
  end
end
