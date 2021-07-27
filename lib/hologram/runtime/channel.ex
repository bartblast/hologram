defmodule Hologram.Runtime.Channel do
  use Phoenix.Channel

  alias Hologram.Compiler.{Helpers, Serializer}
  alias Hologram.Utils

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in("command", payload, socket) do
    response =
      execute_command(payload)
      |> build_response()
      |> Serializer.serialize()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({action, params}) do
    {action, Enum.into(params, %{})}
  end

  defp build_response(action) do
    {action, %{}}
  end

  defp execute_command(%{"command" => command, "params" => params, "context" => context}) do
    command = String.to_atom(command)
    params = Utils.atomize_keys(params)

    context["page_module"]
    |> String.split("_")
    |> tl()
    |> Helpers.module()
    |> apply(:command, [command, params])
  end
end
