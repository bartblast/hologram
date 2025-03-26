defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-mix-tasks-compile-hologram-module1"

  layout Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

  @impl Page
  def template do
    ~HOLO""
  end
end
