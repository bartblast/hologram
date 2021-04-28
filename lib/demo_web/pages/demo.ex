defmodule DemoPage do
  use Hologram.Page

  def state do
    %{
      counter: 0
    }
  end

  def render do
    ~H"""
      <div>Hello World {{ @counter }}</div>
      <div><button :click="increment">Increment</button></div>
    """
  end

  def action(:increment, _params, state) do
    update(state, :counter, state.counter + 1)
  end

  def action(:decrement, _params, state) do
    update(state, :counter, 0)
  end

  # def command(:save_record, value) do
  #   Repo.update(...)
  #   :ok
  # end
end
