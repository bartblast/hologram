defmodule HologramFeatureTests.JavaScriptInteropTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.JavaScriptInterop.AsyncPage
  alias HologramFeatureTests.JavaScriptInterop.DispatchActionPage
  alias HologramFeatureTests.JavaScriptInterop.DispatchEventPage
  alias HologramFeatureTests.JavaScriptInterop.DOMPatchingPage
  alias HologramFeatureTests.JavaScriptInterop.NpmImportPage
  alias HologramFeatureTests.JavaScriptInterop.PendingActionsPage
  alias HologramFeatureTests.JavaScriptInterop.SyncPage

  describe "JS.call/2" do
    feature "calls imported function directly", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Call receiverless function"))
      |> assert_text(css("#call_result"), "{27, true}")
    end

    feature "calls global function", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Call global function"))
      |> assert_text(css("#call_result"), "{42, true}")
    end
  end

  describe "JS.call/3 with sync methods" do
    feature "sync method", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Call sync method"))
      |> assert_text(css("#call_result"), "{3, true}")
    end

    feature "callback interop", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Callback interop"))
      |> assert_text(css("#call_result"), "[2, 4, 6]")
    end
  end

  # Async tests use JS.call/3 but cover JS.call/2 as well, since both go through
  # the same call/4 runtime implementation and Promise handling.
  describe "JS.call/3 with async methods" do
    feature "async method", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Call async method"))
      |> assert_text(css("#call_result"), "{30, true}")
    end

    feature "promise-returning method", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Call promise method"))
      |> assert_text(css("#call_result"), "{300, true}")
    end

    feature "async anonymous function call", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async anonymous function call"))
      |> assert_text(css("#call_result"), "{27, true}")
    end

    feature "async apply", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async apply"))
      |> assert_text(css("#call_result"), "{31, true}")
    end

    feature "async case", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async case"))
      |> assert_text(css("#call_result"), ":matched")
    end

    feature "async comprehension", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async comprehension"))
      |> assert_text(css("#call_result"), "[30, 60, 90]")
    end

    feature "async cond", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async cond"))
      |> assert_text(css("#call_result"), ":correct")
    end

    feature "async dynamic call", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async dynamic call"))
      |> assert_text(css("#call_result"), "{33, true}")
    end

    # TODO: add "async try" feature test once async try expression is fully implemented
  end

  feature "JS.delete/2", %{session: session} do
    session
    |> visit(SyncPage)
    |> click(button("Delete property"))
    |> assert_text(css("#call_result"), ~s({"undefined", true}))
  end

  describe "JS.dispatch_event" do
    feature "dispatch_event/2 (CustomEvent, no opts)", %{session: session} do
      session
      |> visit(DispatchEventPage)
      |> click(button("Dispatch default"))
      |> assert_text(css("#call_result"), ~s("test:alpha"))
    end

    feature "dispatch_event/3 with opts (CustomEvent, with detail)", %{session: session} do
      session
      |> visit(DispatchEventPage)
      |> click(button("Dispatch with detail"))
      |> assert_text(css("#call_result"), "{99, true}")
    end

    feature "dispatch_event/3 with type (MouseEvent, no opts)", %{session: session} do
      session
      |> visit(DispatchEventPage)
      |> click(button("Dispatch with event type"))
      |> assert_text(css("#call_result"), ~s("MouseEvent"))
    end

    feature "dispatch_event/4 (CustomEvent, cancelable)", %{session: session} do
      session
      |> visit(DispatchEventPage)
      |> click(button("Dispatch cancelable"))
      |> assert_text(css("#call_result"), "{false, true}")
    end

    feature "dispatch on :document target", %{session: session} do
      session
      |> visit(DispatchEventPage)
      |> click(button("Dispatch on document"))
      |> assert_text(css("#call_result"), ~s("test:delta"))
    end
  end

  describe "JS.eval/1" do
    feature "sync", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Evaluate expression"))
      |> assert_text(css("#call_result"), "{7, true}")
    end

    feature "async (Promise -> Task)", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async eval"))
      |> assert_text(css("#call_result"), "{88, true}")
    end
  end

  describe "JS.exec/1" do
    feature "sync", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Execute code"))
      |> assert_text(css("#call_result"), "{5, true}")
    end

    feature "async (Promise -> Task)", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async exec"))
      |> assert_text(css("#call_result"), "{66, true}")
    end
  end

  describe "JS.get/2" do
    feature "sync", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Get property"))
      |> assert_text(css("#call_result"), "{10, true}")
    end

    feature "async (Promise -> Task)", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async get"))
      |> assert_text(css("#call_result"), "{77, true}")
    end
  end

  feature "JS.instanceof/2", %{session: session} do
    session
    |> visit(SyncPage)
    |> click(button("Instanceof check"))
    |> assert_text(css("#call_result"), "{true, true}")
  end

  describe "JS.new/2" do
    feature "sync", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("New instance"))
      |> assert_text(css("#call_result"), "{42, true}")
    end

    feature "async (Promise -> Task)", %{session: session} do
      session
      |> visit(AsyncPage)
      |> click(button("Async new"))
      |> assert_text(css("#call_result"), "{51, true}")
    end
  end

  feature "JS.set/3", %{session: session} do
    session
    |> visit(SyncPage)
    |> click(button("Set property"))
    |> assert_text(css("#call_result"), "{20, true}")
  end

  feature "JS.typeof/1", %{session: session} do
    session
    |> visit(SyncPage)
    |> click(button("Typeof value"))
    |> assert_text(css("#call_result"), ~s("object"))
  end

  describe "~JS sigil" do
    feature "DOM manipulation", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Run JS sigil void"))
      |> assert_text(css("#js_sigil_result"), "Hologram")
    end

    feature "return value is boxed", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Run JS sigil returning value"))
      |> assert_text(css("#call_result"), "{11, true}")
    end
  end

  describe "Hologram.dispatchAction()" do
    feature "with params", %{session: session} do
      session
      |> visit(DispatchActionPage)
      |> execute_script(
        "Hologram.dispatchAction('dispatch_with_params', 'page', {amount: 42, label: 'test'});"
      )
      |> assert_text(css("#call_result"), ~s({42, "test"}))
    end

    feature "without params", %{session: session} do
      session
      |> visit(DispatchActionPage)
      |> execute_script("Hologram.dispatchAction('dispatch_without_params', 'page');")
      |> assert_text(css("#call_result"), ":dispatched")
    end

    feature "pending action dispatched before runtime loads", %{session: session} do
      session
      |> visit(PendingActionsPage)
      |> assert_text(css("#call_result"), "{99, true}")
    end
  end

  describe "binding resolution" do
    feature "global", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Resolve global"))
      |> assert_text(css("#call_result"), "{4, true}")
    end

    feature "imported", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Resolve imported"))
      |> assert_text(css("#call_result"), "{12, true}")
    end

    feature "object ref", %{session: session} do
      session
      |> visit(SyncPage)
      |> click(button("Resolve object ref"))
      |> assert_text(css("#call_result"), "{15, true}")
    end
  end

  feature "npm package import", %{session: session} do
    session
    |> visit(NpmImportPage)
    |> click(button("Call npm method"))
    |> assert_text(css("#call_result"), "{123, true}")
  end

  describe "DOM patching" do
    feature "JS-managed subtree is preserved after state change", %{session: session} do
      session
      |> visit(DOMPatchingPage)
      |> click(button("Populate JS subtree"))
      |> assert_text(css("#counter"), "1")
      |> assert_text(css("#js_managed"), "JS managed content")
      |> click(button("Increment counter"))
      |> assert_text(css("#counter"), "2")
      |> assert_text(css("#js_managed"), "JS managed content")
    end
  end
end
