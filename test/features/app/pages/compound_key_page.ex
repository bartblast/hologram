defmodule HologramFeatureTests.CompoundKeyPage do
  use Hologram.Page
  use Hologram.DB

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.WriteError
  alias HologramFeatureTests.Components.CompoundKey.Reactions
  alias HologramFeatureTests.Entities.Reaction

  route "/compound-key"

  layout HologramFeatureTests.Components.DefaultLayout

  state :result, :string

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here
  # may contain another's.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :react_again}> React again in the browser </button>
      <button $click={action: :react_twice}> React twice in the browser </button>
      <button $click={action: :react_with_another_emoji}> React with another emoji in the browser </button>
      <button $click={command: :raise_on_repeated_key}> Raise on a repeated key </button>
      <button $click={command: :repeat_key}> Repeat a key on the server </button>
      <button $click={command: :update_into_repeated_key}> Update into a repeated key </button>
    </p>
    <Reactions cid="reactions" />
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # A key is a question about rows this client may not hold, so the create passes here and the
  # server refuses the batch afterwards.
  def action(:react_again, _params, component) do
    {:ok, _reaction} =
      %{emoji: "thumbs_up", reactor: "ann"}
      |> Reaction.new()
      |> DB.create()

    put_state(component, :result, "reacted_again")
  end

  # One action is one batch: the first row repeats nothing, and goes with the second all the same.
  def action(:react_twice, _params, component) do
    {:ok, _free} =
      %{emoji: "heart", reactor: "bob"}
      |> Reaction.new()
      |> DB.create()

    {:ok, _repeated} =
      %{emoji: "thumbs_up", reactor: "ann"}
      |> Reaction.new()
      |> DB.create()

    put_state(component, :result, "reacted_twice")
  end

  def action(:react_with_another_emoji, _params, component) do
    {:ok, _reaction} =
      %{emoji: "heart", reactor: "ann"}
      |> Reaction.new()
      |> DB.create()

    put_state(component, :result, "reacted_with_heart")
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:raise_on_repeated_key, _params, server) do
    result =
      try do
        %{emoji: "thumbs_up", reactor: "ann"}
        |> Reaction.new()
        |> DB.create!()

        "raised_nothing"
      rescue
        error in WriteError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:repeat_key, _params, server) do
    result =
      %{emoji: "thumbs_up", reactor: "ann"}
      |> Reaction.new()
      |> DB.create()

    put_action(server, :show_result, result: "repeated_key_#{inspect(result)}")
  end

  def command(:update_into_repeated_key, _params, server) do
    {:ok, reaction} =
      %{emoji: "heart", reactor: "ann"}
      |> Reaction.new()
      |> DB.create()

    result =
      reaction
      |> put_attribute(emoji: "thumbs_up")
      |> DB.update()

    put_action(server, :show_result, result: "updated_into_repeated_key_#{inspect(result)}")
  end
end
