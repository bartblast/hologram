defmodule Hologram.Runtime.Channel do
  use Phoenix.Channel
  alias Hologram.Compiler.{Decoder, Helpers, Serializer}

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in("command", %{"context" => context} = payload, socket) do
    response =
      execute_command(payload)
      |> build_response(context)
      |> Serializer.serialize()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({action, params}, context) do
    {action, Enum.into(params, %{}), context}
  end

  defp build_response(action, context) do
    {action, %{}, context}
  end

  defp execute_command(%{"command" => command, "params" => params, "context" => context}) do
    command = String.to_atom(command)

    params =
      Decoder.decode(params)
      |> Enum.into(%{})

    context["page_module"]
    |> String.split("_")
    |> tl()
    |> Helpers.module()
    |> apply(:command, [command, params])
  end
end
