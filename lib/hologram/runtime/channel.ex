# TODO: already refactored, test

defmodule Hologram.Channel do
  use Phoenix.Channel
  alias Hologram.Compiler.Helpers

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in("command", payload, socket) do
    response =
      run_command(payload)
      |> build_response()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({action, params}) do
    [action, Enum.into(params, %{})]
  end

  defp build_response(action) do
    [action, %{}]
  end

  defp run_command(%{"command" => command, "params" => params, "context" => context}) do
    command = String.to_atom(command)

    context["page_module"]
    |> String.split("_")
    |> tl()
    |> Helpers.module()
    |> apply(:command, [command, params])
  end
end
