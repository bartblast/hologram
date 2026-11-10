defmodule Hologram.Test.Fixtures.Template.Renderer.Module120 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module120"

  layout Hologram.Test.Fixtures.Template.Renderer.Module118

  @impl Page
  def template do
    ~HOLO"""
    <p $ref={:shared}></p>
    """
  end
end
