defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module8 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module10

  route "/hologram-test-fixtures-mix-tasks-compile-hologram-module8"

  layout Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module9

  @impl Page
  def template do
    ~HOLO"""
    <input $ref="search" /><Module10 />
    """
  end
end
