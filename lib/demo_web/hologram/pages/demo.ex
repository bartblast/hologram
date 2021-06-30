defmodule DemoPage do
  use Hologram.Page

  route "/demo"

  def state do
    %{
      counter: 0
    }
  end

  def template do
    ~H"""
    <body>
      <h1>Demo Page</h1>
      <Counter value={{ @counter }} />
      <div><button :click="increment">Increment</button></div>
    </body>
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
