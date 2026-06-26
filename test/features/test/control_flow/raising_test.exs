defmodule HologramFeatureTests.ControlFlow.RaisingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.RaisingPage

  feature "raise with module", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my message",
                        fn ->
                          session
                          |> visit(RaisingPage)
                          |> click(button("Raise Module"))
                        end
  end

  feature "raise with string", %{session: session} do
    assert_client_error session,
                        RuntimeError,
                        "my string",
                        fn ->
                          session
                          |> visit(RaisingPage)
                          |> click(button("Raise String"))
                        end
  end

  feature "throw", %{session: session} do
    assert_js_error session,
                    ~s/(throw) "my value"/,
                    fn ->
                      session
                      |> visit(RaisingPage)
                      |> click(button("Throw"))
                    end
  end

  feature "exit", %{session: session} do
    assert_js_error session,
                    ~s/(exit) "my reason"/,
                    fn ->
                      session
                      |> visit(RaisingPage)
                      |> click(button("Exit"))
                    end
  end
end
