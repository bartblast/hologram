defmodule Hologram.Test.Fixtures.Template.Renderer.Module152 do
  use Hologram.Page

  route "/hologram-test-fixtures-template-renderer-module152/:name"

  param :name, :string

  layout Hologram.Test.Fixtures.Template.Renderer.Module26

  state :suffix, :string, default: "!"

  derived :prop_1, :string, fn name, suffix -> name <> suffix end

  derived :prop_3, :string, fn name -> String.upcase(name) end

  @impl Page
  def template do
    ~HOLO"page derived = {@prop_1} {@prop_3}"
  end
end
