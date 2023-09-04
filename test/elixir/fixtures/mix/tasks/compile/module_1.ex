defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Module1 do
  use Hologram.Page

  route "/hologram-test-fixtures-mix-tasks-compile-module1"

  layout Hologram.Test.Fixtures.Mix.Tasks.Compile.Module2

  @impl Page
  def template do
    ~H""
  end
end
