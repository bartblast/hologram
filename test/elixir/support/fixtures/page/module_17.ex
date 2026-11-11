defmodule Hologram.Test.Fixtures.Page.Module17 do
  use Hologram.Page

  route "/hologram-test-fixtures-page-module17/:project_id"

  param :project_id, :integer

  layout Hologram.Test.Fixtures.Page.Module4

  state :page_size, :integer, default: 10

  derived :label, :string, fn project_id, page_size -> "#{project_id}/#{page_size}" end

  @impl Page
  def template do
    ~HOLO""
  end
end
