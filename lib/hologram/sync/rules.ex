defmodule Hologram.Sync.Rules do
  @moduledoc false

  # The rules this node enforces, rendered for a client whose bundle was built with other ones (see
  # `Hologram.Compiler.render_rules/1`). A deploy that changes rules sends every client coming back
  # through here at once, so they are rendered once per compile rather than once per client.

  alias Hologram.Compiler
  alias Hologram.Entity.Model

  @cache_key {__MODULE__, :rendered}

  @doc """
  Returns the rules of the project's compiled data model rendered for the client.

  Rendered on the first call and cached, since every client a deploy sends back asks at once. A
  compile drops the cache with the model facts, so rules it changed are rendered again. Raises
  while the data model is under a hold (see `Hologram.Entity.Model.ensure_released!/0`).
  """
  @spec rendered() :: String.t()
  def rendered do
    Model.ensure_released!()

    case :persistent_term.get(@cache_key, nil) do
      nil ->
        rules = Compiler.render_rules(Model.entity_types())

        :persistent_term.put(@cache_key, rules)

        rules

      rules ->
        rules
    end
  end

  @doc false
  @spec reset_cache() :: :ok
  def reset_cache do
    :persistent_term.erase(@cache_key)

    :ok
  end
end
