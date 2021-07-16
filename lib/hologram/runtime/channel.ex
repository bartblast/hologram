# DEFER: refactor & test

defmodule Hologram.Channel do
  use Phoenix.Channel
  alias Hologram.Compiler.Helpers

  def join("hologram", _payload, socket) do
    {:ok, socket}
  end

  def handle_in("command", payload, socket) do
    %{
      "command" => command,
      "context" => context,
      "params" => params
    } = payload

    command = String.to_atom(command)

    # TODO: handle modules with multiple name segments
    result =
      context["page_module"]
      |> String.to_atom()
      |> (&[&1]).()
      |> Helpers.module()
      |> apply(:command, [command, params])

    payload =
      case result do
        {_action, _params} ->
          # TODO: implement
          [result, []]
        _ ->
          [result, []]
      end

    {:reply, {:ok, payload}, socket}
  end
end
