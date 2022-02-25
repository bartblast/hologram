defmodule Hologram.E2E.Operators.ModuleAttributePage do
  use Hologram.Page

  @test_attribute "test_value"

  route "/e2e/operators/module-attribute"

  def init do
    %{
      result: 0
    }
  end

  def template do
    ~H"""
    <button id="button" on:click="calculate">Calculate</button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:calculate, _params, state) do
    Map.put(state, :result, @test_attribute)
  end
end
