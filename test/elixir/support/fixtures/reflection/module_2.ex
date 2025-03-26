defmodule Hologram.Test.Fixtures.Reflection.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-commons-reflection-module2"

  layout Hologram.Test.Fixtures.Reflection.Module4

  @impl Page
  def template do
    ~HOLO"""
    Module2 template
    """
  end
end
