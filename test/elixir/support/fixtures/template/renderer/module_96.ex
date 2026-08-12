defmodule Hologram.Test.Fixtures.Template.Renderer.Module96 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Entity.Module15

  route "/hologram-test-fixtures-template-renderer-module96"

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def init(_params, component, server) do
    row = %Module15{
      id: "test-id-96",
      label: "Report",
      secret_note: "note_secret_v3",
      token: "tok_D8vN"
    }

    {put_state(component, :row, row), server}
  end

  @impl Page
  def template do
    ~HOLO"""
    page template
    """
  end
end
