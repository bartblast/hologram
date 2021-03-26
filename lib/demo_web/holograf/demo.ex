defmodule Demo do
  use Holograf.Page

  # def state do
  #   %{
  #     a: 1,
  #     b: 2
  #   }
  # end

  def action(:increment, _params, state) do
    assign(state, :counter, 1)
  end

  def action(:decrement, _params, state) do
    assign(state, :counter, 0)
  end

  # def command(:save_record, value) do
  #   Repo.update(...)
  #   :ok
  # end
end
