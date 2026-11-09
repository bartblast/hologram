defmodule Hologram.Test.Fixtures.Template.Renderer.Module111 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module111"

  layout Hologram.Test.Fixtures.Template.Renderer.Module112

  @impl Page
  def template do
    ~HOLO""
  end
end
