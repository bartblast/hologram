defmodule Hologram.Runtime.Channel do
  use Phoenix.Channel

  alias Hologram.Compiler.{Decoder, Serializer}
  alias Hologram.Conn
  alias Hologram.Template.Renderer

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in(
        "command",
        %{"target_module" => target_module, "target_id" => target_id} = payload,
        socket
      ) do
    target_module = Decoder.decode(target_module)
    target_id = Decoder.decode(target_id)

    response =
      execute_command(target_module, payload)
      |> build_response(target_id)
      |> Serializer.serialize()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({target_id, action, params}, _) do
    {target_id, action, Enum.into(params, %{})}
  end

  defp build_response({target_id, action}, _) when is_atom(action) do
    {target_id, action, %{}}
  end

  defp build_response({action, params}, target_id) do
    {target_id, action, Enum.into(params, %{})}
  end

  defp build_response(action, target_id) do
    {target_id, action, %{}}
  end

  defp execute_command(target_module, %{"command" => command, "params" => params}) do
    command = Decoder.decode(command)

    params =
      Decoder.decode(params)
      |> Enum.into(%{})

    if command == :__redirect__ do
      html = Renderer.render(params.page, %Conn{}, %{})
      # DEFER: inject params
      url = params.page.route()
      {:__redirect__, html: html, url: url}
    else
      apply(target_module, :command, [command, params])
    end
  end
end
