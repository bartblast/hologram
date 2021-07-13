defmodule DemoPage do
  use Hologram.Page

  route("/demo")

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
      <div><button on_click="increment">Increment</button></div>
    </body>
    """
  end

  def action(:increment, _params, state) do
    update(state, :counter, state.counter + 1)
  end

  def action(:decrement, _params, state) do
    update(state, :counter, 0)
  end

  def command(:run_command, _params) do
    IO.puts("command started")
    :timer.sleep(5_000)
    IO.puts("command finished")

    :command_finished
  end
end
