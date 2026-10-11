defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module3 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module4
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module5

  route "/hologram-test-fixtures-mix-tasks-compile-hologram-module3"

  layout Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

  @impl Page
  def template do
    ~HOLO"{Module4.my_fun()}<Module5 />"
  end
end
