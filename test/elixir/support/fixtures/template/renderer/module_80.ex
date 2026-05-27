defmodule Hologram.Test.Fixtures.Template.Renderer.Module80 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Template.Renderer.Module81

  route "/hologram-test-fixtures-template-renderer-module80"

  layout Module81

  @impl Page
  def template do
    ~HOLO""
  end
end
