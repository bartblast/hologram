defmodule Hologram.Test.Fixtures.Template.Renderer.Module160 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module160/:name"

  param :name, :string

  layout Hologram.Test.Fixtures.Template.Renderer.Module159

  state :suffix, :string, default: "!"

  derived :label, :string, fn name, suffix -> name <> suffix end

  @impl Page
  def template do
    ~HOLO"page {@label}"
  end
end
