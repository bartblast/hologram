# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Builder.Module5 do
  use Hologram.Page
  alias Hologram.Test.Fixtures.Compiler.Builder.Module7

  layout Hologram.Test.Fixtures.Compiler.Builder.Module6

  def action(:action_5a, params, state) do
    Module7.my_fun_7a(params, state)
  end

  def action(:action_5b, _params, state) do
    state
    |> Enum.to_list()
    |> :erlang.hd()
  end
end
