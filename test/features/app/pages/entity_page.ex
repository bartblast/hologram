defmodule HologramFeatureTests.EntityPage do
  use Hologram.Page
  use Hologram.DB

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Entities.Item
  alias HologramFeatureTests.Entities.Review

  route "/entity"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # Every one of these runs in the BROWSER, which is the whole point: an action reaches the ported
  # Entity.new and Entity.validate, and those read the declarations the build baked rather than
  # the entity module, which ships no reflection here.
  #
  # A button is clicked by a label the browser driver matches as a SUBSTRING, so no label here may
  # contain another's - which is why each one names what it builds rather than sharing a verb.
  def template do
    ~HOLO"""
    <p>
      <button $click={action: :build_with_defaults}> Build with defaults </button>
      <button $click={action: :refuse_relationship_assignment}> Assign a relationship </button>
      <button $click={action: :validate_changes}> Check a range </button>
      <button $click={action: :validate_format}> Check a pattern </button>
      <button $click={action: :validate_struct}> Check a whole struct </button>
      <button $click={action: :validate_valid}> Accept good changes </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:build_with_defaults, _params, component) do
    item = Entity.new(Item, name: "shelf")

    put_state(component, :result, "defaults_#{item.stock}_#{inspect(item.created_at)}")
  end

  def action(:refuse_relationship_assignment, _params, component) do
    result =
      try do
        Entity.new(Review, product: "id_1")
      rescue
        error in ArgumentError -> error.message
      end

    put_state(component, :result, "refused_#{result}")
  end

  def action(:validate_changes, _params, component) do
    {:error, %{rating: [{:in, range}]}} = Entity.validate(Review, %{rating: 9})

    put_state(component, :result, "changes_#{range.first}_#{range.last}")
  end

  # The pattern travels as its source and is compiled in the browser, so what a violation carries
  # is a regex struct rather than the text the declaration held.
  def action(:validate_format, _params, component) do
    {:error, %{author_email: [{:format, regex}]}} =
      Entity.validate(Review, %{author_email: "nope"})

    put_state(component, :result, "format_#{regex.source}")
  end

  def action(:validate_struct, _params, component) do
    {:error, %{stock: [{:min, min}]}} =
      Item
      |> Entity.new(name: "shelf", stock: -1)
      |> Entity.validate()

    put_state(component, :result, "struct_#{min}")
  end

  def action(:validate_valid, _params, component) do
    put_state(component, :result, "valid_#{inspect(Entity.validate(Review, rating: 3))}")
  end
end
