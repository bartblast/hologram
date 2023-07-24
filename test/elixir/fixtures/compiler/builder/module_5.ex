defmodule Hologram.Test.Fixtures.Compiler.Builder.Module5 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Builder.Module7

  layout Hologram.Test.Fixtures.Compiler.Builder.Module6

  def action(:my_action, params, state) do
    Module7.my_fun_7a(params, state)
  end
end
