# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module180 do
  use Hologram.Component

  prop :change_each_time, :boolean, default: false
  prop :user_id, :string

  @impl Component
  def init(props, component, server) do
    inits = Process.get(:module_180_inits, 0) + 1
    Process.put(:module_180_inits, inits)

    user_id = if props.change_each_time, do: "user-#{inits}", else: props.user_id

    server =
      server
      |> sign_in()
      |> put_user_id(user_id)

    {component, server}
  end

  # What a sign-in sets along with the user, which the render for that user no longer does.
  defp sign_in(%{user_id: nil} = server) do
    server
    |> put_session(:signed_in_by, "module_180")
    |> put_cookie("welcome", "module_180")
    |> put_response_header("x-signed-in-by", "module_180")
  end

  defp sign_in(server), do: server

  @impl Component
  def template do
    ~HOLO"child"
  end
end
