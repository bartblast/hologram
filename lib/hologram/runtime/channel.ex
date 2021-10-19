defmodule Hologram.Runtime.Channel do
  use Phoenix.Channel

  alias Hologram.Compiler.{Decoder, Serializer}
  alias Hologram.Template.Renderer

  def join("hologram", _, socket) do
    {:ok, socket}
  end

  def handle_in("command", %{"target" => target} = payload, socket) do
    target = Decoder.decode(target)

    response =
      execute_command(target, payload)
      |> build_response(target)
      |> Serializer.serialize()

    {:reply, {:ok, response}, socket}
  end

  defp build_response({action, params}, target) do
    {target, action, Enum.into(params, %{})}
  end

  defp build_response(action, target) do
    {target, action, %{}}
  end

  defp execute_command(target, %{"command" => command, "params" => params}) do
    command = Decoder.decode(command)

    params =
      Decoder.decode(params)
      |> Enum.into(%{})

    if command == :__redirect__ do
      html = Renderer.render(params.page, %{})
      # DEFER: inject params
      url = params.page.route()
      {:__redirect__, html: html, url: url}
    else
      apply(target, :command, [command, params])
    end
  end
end
