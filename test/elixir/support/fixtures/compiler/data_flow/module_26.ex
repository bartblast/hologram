# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module26 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25

  def init(_props, component, _server) do
    state = %{
      loader: fn query -> Module25.reads_loaded(query) end,
      reader: fn query -> Module25.reads(query) end
    }

    %{component | state: state}
  end

  def template do
    ~HOLO""
  end
end
