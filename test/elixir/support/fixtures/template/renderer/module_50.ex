defmodule Hologram.Test.Fixtures.Template.Renderer.Module50 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module50"

  param :key_1, :integer
  param :key_2, :string

  layout Hologram.Test.Fixtures.Template.Renderer.Module49

  @impl Page
  def template do
    ~HOLO"""
    page Module50 template
    """
  end
end
