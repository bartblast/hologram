# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module94 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Entity.Module14, as: User

  prop :current_user, User, from_context: {Hologram, :current_user}

  @impl Component
  def template do
    ~HOLO"""
    current user = {if(@current_user, do: @current_user.email, else: "none")}
    """
  end
end
