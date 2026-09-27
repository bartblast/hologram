defmodule HologramEcosystemTests.Ash.CustomTypesTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias HologramEcosystemTests.Ash.Domain
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note
  alias HologramEcosystemTests.Ash.Reader
  alias HologramEcosystemTests.Ash.Types.Stamp

  setup do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Domain, %{exception?: false}},
        {Item, %{exception?: false}},
        {Note, %{exception?: false}},
        {Reader, %{exception?: false}},
        {Stamp, %{exception?: false}}
      ])

    [flow: DataFlow.start(PLT.start(), module_info_plt)]
  end

  defp structs(function, flow) do
    summary = DataFlow.summary({Reader, function, 1}, flow)
    DataFlow.types(summary, flow).structs
  end

  test "a field of a custom type, of a record from an interface, holds what the type casts to", %{
    flow: flow
  } do
    assert Date in structs(:stamp_by_interface, flow)
  end

  test "a field of a custom type, of a record from Ash's API, holds what the type casts to", %{
    flow: flow
  } do
    assert Date in structs(:stamp_by_api, flow)
  end
end
