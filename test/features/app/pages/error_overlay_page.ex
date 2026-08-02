defmodule HologramFeatureTests.ErrorOverlayPage do
  use Hologram.Page

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]

  # inner_fun/0 always raises, so nothing leading to it returns either.
  @dialyzer {:no_return, [action: 3, inner_fun: 0, middle_fun: 0, outer_fun: 0]}

  route "/error-overlay"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <strong>Scenarios</strong>
      <button $click="no_matching_clause"> No matching clause </button>
      <button $click="raise_error"> Raise error </button>
    </p>
    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  # The overlay sets the page's own frames against the framework's, so the chain
  # below is deep enough to show a run of them. Every call leading to the raise
  # is non-tail - its result lands in a tuple, or another expression follows it -
  # because the BEAM's last-call optimization would otherwise drop the caller's
  # frame from the trace.

  def action(:no_matching_clause, _params, component) do
    # The argument is wrapped so the clause it doesn't match is found at runtime,
    # which is where the overlay reports from.
    only_tuple(wrap_term(:not_a_tuple))
    component
  end

  def action(:raise_error, _params, component) do
    outer_fun()
    component
  end

  defp inner_fun, do: raise("overlaid error")

  defp middle_fun, do: {:middle, inner_fun()}

  defp only_tuple({_first, _second}), do: :ok

  defp outer_fun, do: {:outer, middle_fun()}
end
