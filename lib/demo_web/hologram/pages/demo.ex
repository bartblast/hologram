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
    {update(state, :counter, state.counter + 1), :run_command}

    # DEFER: implement
    # alternative API when there is no command or redirect
    # new state

    # DEFER: implement
    # alternative API for piping:
    # update(state, abc: 123, xyz: 987)
    # |> push_command(:some_command, abc: 123, xyz: 987)
    # |> push_redirect(SomePage, abc: 123, xyz: 987)
  end

  def action(:decrement, _params, state) do
    update(state, :counter, 0)
  end

  def command(:run_command, _params) do
    :timer.sleep(5_000)
    :some_action

    # DEFER: implement
    # alternative API when there are action param:
    # {:some_action, abc: 123, xyz: 987)

    # DEFER: implement
    # alternative API for piping:
    # push_action(:some_action, abc: 123, xyz: 987)
    # |> push_redirect(SomePage, abc: 123, xyz: 987)
  end
end
