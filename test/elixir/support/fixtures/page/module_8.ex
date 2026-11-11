defmodule Hologram.Test.Fixtures.Page.Module8 do
  use Hologram.Page

  param :id, :integer

  state :count, :integer, default: 0
  state :user, :map

  route "/hologram-test-fixtures-page-module8/:id"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end
end
