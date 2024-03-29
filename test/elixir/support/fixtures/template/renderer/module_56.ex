# Used only in client tests.
defmodule Hologram.Test.Fixtures.Template.Renderer.Module56 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module56"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~H"""
    <div>
      <button $click="my_action">Click me</button>
    </div>
    """
  end
end
