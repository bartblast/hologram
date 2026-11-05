defmodule HologramCowboyTests.TestCase do
  use ExUnit.CaseTemplate

  alias Hologram.Test.BrowserSession
  alias Wallaby.Feature.Utils

  # Based on Wallaby.Feature.__using__/1
  using do
    quote do
      ExUnit.Case.register_attribute(__MODULE__, :sessions)

      # Kernel.tap/2 conflicts with Browser.tap/2
      import Kernel, except: [tap: 2]

      # visit/2 comes from Hologram.Test.FeatureHelpers, which takes a page module
      # rather than a path.
      import Hologram.Test.FeatureHelpers
      import HologramCowboyTests.Helpers
      import Wallaby.Browser, except: [visit: 2]
      import Wallaby.Feature
      import Wallaby.Query

      setup context do
        # Waits for Wallaby to end the test's browser sessions, restarting a session
        # store stuck on a browser that stopped answering, so it doesn't fail the
        # tests after it.
        test_pid = self()
        on_exit(fn -> BrowserSession.await_teardown(test_pid) end)

        metadata = Utils.maybe_checkout_repos(context[:async])

        # Retries a session start that gets no answer.
        start_session_opts =
          Utils.put_create_session_fn(
            [metadata: metadata],
            context[:create_session_fn] || (&BrowserSession.create_session/2)
          )

        context
        |> get_in([:registered, :sessions])
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
  end
end
