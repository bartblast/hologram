defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module7 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Reflection.Module5

  route "/hologram-test-fixtures-mix-tasks-compile-hologram-module7"

  layout Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

  @impl Page
  def action(:my_action, _params, component) do
    put_state(component, :value, %Module5{})
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
