defmodule Hologram.ExJsConsistency.TypeTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir consistency test has a related JavaScript test in test/javascript/type_test.mjs (consistency tests section)
  Always update both together.
  """
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Component
  alias Hologram.Component.Action
  alias Hologram.Component.Command

  @moduletag :consistency

  test "action struct" do
    assert %Action{} == %{__struct__: Action, name: nil, params: %{}, target: nil}
  end

  test "command struct" do
    assert %Command{} == %{__struct__: Command, name: nil, params: %{}, target: nil}
  end

  test "component struct" do
    assert %Component{} == %{
             __struct__: Component,
             emitted_context: %{},
             next_action: nil,
             next_command: nil,
             next_page: nil,
             state: %{}
           }
  end
end
