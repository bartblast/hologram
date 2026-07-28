# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.ExJsConsistency.Erlang.Module3 do
  @moduledoc """
  Custom :error_info format module used by :erlang.error/3 consistency tests.
  """

  def format_error(_reason, [{_module, _function, _args, _info} | _rest]) do
    %{2 => "not a map"}
  end
end
