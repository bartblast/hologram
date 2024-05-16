defmodule Module1 do
  use Hologram.Component

  def action(:my_action_1, %{a: a, b: b, event: event}, component) do
    component
    |> put_state(:c, a + b + 1)
    |> put_context(:event, event)
  end

  def template do
    ~H""
  end
end
