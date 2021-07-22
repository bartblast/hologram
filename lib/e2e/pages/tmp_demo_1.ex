defmodule Demo.TmpDemo1 do
  use Hologram.Page

  route "/demo"

  def state do
    %{
      counter: 0,
      text: "abc"
    }
  end

  def template do
    ~H"""
    <body>
      <h1>Demo Page</h1>
      <Counter value={@counter} />
      <div><button on_click="increment">Increment</button></div>
      <div>{@text}</div>
      <form on_submit="submit_form">
        <input type="text" name="email" />
        <input type="text" name="first_name" />
        <button type="submit">Submit</button>
      </form>
    </body>
    """
  end

  def action(:increment, _params, state) do
    {update(state, :counter, state.counter + 1), :some_command}

    # explicit mode:
    # state
    # update(state, abc: 123, xyz: 987)
    # {state, :some_command}
    # {state, :some_command, abc: 123, bcd: 234}
    # {state, PageModule}
    # {state, PageModule, abc: 123, bcd: 234}
    #
    # pipe mode:
    # update(state, abc: 123, xyz: 987)
    # |> push_command(:some_command, abc: 123, xyz: 987)
    # |> push_redirect(SomePage, abc: 123, xyz: 987)
  end

  def action(:decrement, _params, state) do
    update(state, :counter, 0)
  end

  def action(:update_text_1, _params, state) do
    update(state, :text, "hello!")
  end

  def action(:submit_form, params, state) do
    {state, :save_form, params}
  end

  def command(:some_command, _params) do
    :update_text_1

    # DEFER: implement
    # alternative API when there are action param:
    # {:some_action, abc: 123, xyz: 987)

    # DEFER: implement
    # alternative API for piping:
    # push_action(:some_action, abc: 123, xyz: 987)
    # |> push_redirect(SomePage, abc: 123, xyz: 987)
  end

  def command(:save_form, params) do
    IO.inspect(params)
    :update_text_1
  end
end
