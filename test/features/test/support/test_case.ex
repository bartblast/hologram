defmodule HologramFeatureTestsWeb.TestCase do
  use ExUnit.CaseTemplate

  # Based on Wallaby.Feature.__using__/1
  using do
    quote do
      ExUnit.Case.register_attribute(__MODULE__, :sessions)

      # Kernel.tap/2 was introduced in 1.12 and conflicts with Browser.tap/2
      import Kernel, except: [tap: 2]

      import HologramFeatureTestsWeb.Test.Helpers
      import Wallaby.Browser, except: [visit: 2]
      import Wallaby.Feature
      import Wallaby.Query

      setup context do
        metadata = Wallaby.Feature.Utils.maybe_checkout_repos(context[:async])

        start_session_opts =
          [metadata: metadata]
          |> Wallaby.Feature.Utils.put_create_session_fn(context[:create_session_fn])

        get_in(context, [:registered, :sessions])
        |> Wallaby.Feature.Utils.sessions_iterable()
        |> Enum.map(fn
          opts when is_list(opts) ->
            Wallaby.Feature.Utils.start_session(opts, start_session_opts)

          i when is_number(i) ->
            Wallaby.Feature.Utils.start_session([], start_session_opts)
        end)
        |> Wallaby.Feature.Utils.build_setup_return()
      end
    end
  end
end
