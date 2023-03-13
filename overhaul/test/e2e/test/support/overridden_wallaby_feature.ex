defmodule HologramE2E.OverriddenWallabyFeature do
  alias Wallaby.Feature.Utils

  defmacro __using__(_) do
    quote do
      ExUnit.Case.register_attribute(__MODULE__, :sessions)

      alias HologramE2E.OverriddenWallabyFeature
      alias Wallaby.Browser
      alias Wallaby.Element
      alias Wallaby.Query

      # Kernel.tap/2 was introduced in 1.12 and conflicts with Browser.tap/2
      import Kernel, except: [tap: 2]

      import Wallaby.Browser, except: [click: 2, visit: 2]
      import Wallaby.Feature

      setup context do
        OverriddenWallabyFeature.setup_feature(context)
      end
    end
  end

  def setup_feature(context) do
    metadata = Utils.maybe_checkout_repos(context[:async])

    start_session_opts =
      [metadata: metadata]
      |> Utils.put_create_session_fn(context[:create_session_fn])

    get_in(context, [:registered, :sessions])
    |> Utils.sessions_iterable()
    |> Enum.map(fn
      opts when is_list(opts) ->
        Utils.start_session(opts, start_session_opts)

      i when is_number(i) ->
        Utils.start_session([], start_session_opts)
    end)
    |> Utils.build_setup_return()
  end
end
