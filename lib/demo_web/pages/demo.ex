defmodule DemoPage do
  use Hologram.Page

  def state do
    %{
      a: 123,
      b: 234
    }
  end

  def render(state) do
    ~H"""
      <div>Hello World {{ @a }}</div>
    """
  end

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
