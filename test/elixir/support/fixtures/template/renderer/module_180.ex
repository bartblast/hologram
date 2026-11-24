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

    {component, put_user_id(server, user_id)}
  end

  @impl Component
  def template do
    ~HOLO"child"
  end
end
