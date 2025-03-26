defmodule Hologram.Test.Fixtures.Template.Renderer.Module45 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module45"

  layout Hologram.Test.Fixtures.Template.Renderer.Module44

  @impl Page
  def template do
    ~HOLO""
  end
end
