defmodule HologramEcosystemTests.Ash.OpaqueTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ash, as: AshRules
  alias HologramEcosystemTests.Ash.Reader

  setup do
    [flow: DataFlow.start(PLT.start(), PLT.start())]
  end

  test "a function of Ash's internals gives its top", %{flow: flow} do
    mfa = {Ash.Filter, :parse, 2}

    assert AshRules.summary(mfa, flow) == DataFlow.top(mfa)
  end

  test "a function of Ash that no rule answers gives its top", %{flow: flow} do
    mfa = {Ash, :can?, 3}

    assert AshRules.summary(mfa, flow) == DataFlow.top(mfa)
  end

  test "a function of an extension gives its top", %{flow: flow} do
    mfa = {AshMoney.Types.Money, :cast_input, 2}

    assert AshRules.summary(mfa, flow) == DataFlow.top(mfa)
  end

  test "a module the app defines in Ash's namespace is followed", %{flow: flow} do
    assert AshRules.summary({Ash.EcosystemProbe, :value, 0}, flow) == nil
  end

  test "the app's own module is followed", %{flow: flow} do
    assert AshRules.summary({Reader, :title, 1}, flow) == nil
  end
end
