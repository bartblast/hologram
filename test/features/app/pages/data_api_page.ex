defmodule HologramFeatureTests.DataApiPage do
  use Hologram.Page
  use Hologram.Query

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review

  route "/data-api"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click={command: :create_review}> Create review </button>
      <button $click={command: :reject_invalid_review}> Reject invalid review </button>
      <button $click={command: :run_query}> Run query </button>
      <button $click={command: :validate_changes}> Validate changes </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def action(:show_result, params, component) do
    put_state(component, :result, params.result)
  end

  def command(:create_review, _params, server) do
    product =
      Product
      |> Entity.new(name: "create_review_product")
      |> DB.create!()

    review =
      Review
      |> Entity.new(product_id: product.id, rating: 4)
      |> DB.create!()

    persisted_review = DB.get(Review, review.id)

    put_action(server, :show_result, result: "created_review_#{persisted_review.rating}")
  end

  def command(:reject_invalid_review, _params, server) do
    product =
      Product
      |> Entity.new(name: "reject_invalid_review_product")
      |> DB.create!()

    result =
      try do
        Review
        |> Entity.new(product_id: product.id, rating: 0)
        |> DB.create!()

        "rejected_nothing"
      rescue
        error in ArgumentError -> error.message
      end

    put_action(server, :show_result, result: result)
  end

  def command(:run_query, _params, server) do
    Enum.each(["run_query_banana", "run_query_apple", "run_query_excluded"], fn name ->
      Product
      |> Entity.new(name: name)
      |> DB.create!()
    end)

    names =
      Product
      |> filter(name: {:!=, "run_query_excluded"})
      |> order_by(:name)
      |> DB.run()
      |> Enum.map_join(",", & &1.name)

    put_action(server, :show_result, result: names)
  end

  def command(:validate_changes, _params, server) do
    validation_result = Entity.validate(Review, %{rating: 9})

    put_action(server, :show_result, result: "validated_#{inspect(validation_result)}")
  end
end
