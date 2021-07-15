# DEFER: refactor & test

defmodule Hologram.Channel do
  use Phoenix.Channel
  alias Hologram.Compiler.Helpers

  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  def handle_in("command", %{"command" => command, "context" => context} = request, socket) do
    command = String.to_atom(command)

    # TODO: handle modules with multiple name segments
    result =
      context["page_module"]
      |> String.to_atom()
      |> (&[&1]).()
      |> Helpers.module()
      |> apply(:command, [command, %{}])

    {:reply, {:ok, result}, socket}
  end
end
