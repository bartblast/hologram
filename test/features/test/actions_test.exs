defmodule HologramFeatureTests.ActionsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Actions.Page1
  alias HologramFeatureTests.Actions.Page10
  alias HologramFeatureTests.Actions.Page11
  alias HologramFeatureTests.Actions.Page12
  alias HologramFeatureTests.Actions.Page13
  alias HologramFeatureTests.Actions.Page14
  alias HologramFeatureTests.Actions.Page15
  alias HologramFeatureTests.Actions.Page16
  alias HologramFeatureTests.Actions.Page17
  alias HologramFeatureTests.Actions.Page18
  alias HologramFeatureTests.Actions.Page19
  alias HologramFeatureTests.Actions.Page2
  alias HologramFeatureTests.Actions.Page20
  alias HologramFeatureTests.Actions.Page21
  alias HologramFeatureTests.Actions.Page22
  alias HologramFeatureTests.Actions.Page23
  alias HologramFeatureTests.Actions.Page24
  alias HologramFeatureTests.Actions.Page25
  alias HologramFeatureTests.Actions.Page26
  alias HologramFeatureTests.Actions.Page27
  alias HologramFeatureTests.Actions.Page3
  alias HologramFeatureTests.Actions.Page4
  alias HologramFeatureTests.Actions.Page5
  alias HologramFeatureTests.Actions.Page6
  alias HologramFeatureTests.Actions.Page7
  alias HologramFeatureTests.Actions.Page8
  alias HologramFeatureTests.Actions.Page9

  describe "syntax" do
    feature "text syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_1']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_1, %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression shorthand syntax without params", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_2']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_2, %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression shorthand syntax with params", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_3']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "expression longhand syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_4']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_4, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "multi-chunk syntax", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_5']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_5, %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "layout action" do
    feature "triggered from layout (default target)", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_1']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_action_1, %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_2']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_action_2, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='layout_action_3']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_action_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "page action" do
    # Covered in preceding (syntax) tests:
    # feature "triggered from page (default target)"

    feature "triggered from layout", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_6']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_6, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_7']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_action_7, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "component action" do
    feature "triggered from layout", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_3']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{:component_1_action_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_2']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{:component_1_action_2, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component (default target)", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='component_1_action_1']"))
      |> assert_text(
        css("#component_1_result"),
        ~r/\{:component_1_action_1, %\{event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "component struct mutations" do
    feature "emitted context", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_8']"))
      |> assert_text(css("#component_1_prop_1"), ":updated_value")
    end

    feature "next action", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_9']"))
      |> assert_text(css("#page_result"), ~s/{:page_action_10, %{x: 10, y: 20}}/)
    end

    feature "next action executes exactly once", %{session: session} do
      session
      |> visit(Page19)
      |> click(button("Run Page 19 Action A"))
      |> assert_text(css("#page_result"), "{:page_19_action_b, 1}")
      |> click(button("Run Page 19 Action C"))
      |> assert_text(css("#page_result"), "{:page_19_action_c, 1}")
    end

    feature "next command", %{session: session} do
      session
      |> visit(Page1)
      |> click(css("button[id='page_action_11']"))
      |> assert_text(css("#page_result"), ~s/{:page_action_12, %{x: 10, y: 20}}/)
    end

    # Covered in navigation test suite
    # feature "next page"

    # Covered in preceding (syntax) tests:
    # feature "state"
  end

  describe "actions queued in server-side init/3" do
    feature "page init/3, target not specified", %{session: session} do
      session
      |> visit(Page2)
      |> assert_text(css("#page_result"), ~s'{:page_action_result, %{queued_from: :page}}')
    end

    feature "page init/3, target is specified", %{session: session} do
      session
      |> visit(Page3)
      |> assert_text(
        css("#component_1_result"),
        ~s'{:component_1_action_result, %{queued_from: :page}}'
      )
    end

    feature "page init/3 action executes exactly once", %{session: session} do
      session
      |> visit(Page16)
      |> assert_text(css("#page_result"), "{:page_16_action_a, 1}")
      |> click(button("Run Page 16 Action B"))
      |> assert_text(css("#page_result"), "{:page_16_action_b, 1}")
    end

    feature "component init/3, target not specified", %{session: session} do
      session
      |> visit(Page4)
      |> assert_text(
        css("#component_2_result"),
        ~s'{:component_2_action_result, %{queued_from: :component_2}}'
      )
    end

    feature "component init/3, target is specified", %{session: session} do
      session
      |> visit(Page5)
      |> assert_text(
        css("#component_4_result"),
        ~s'{:component_4_action_result, %{queued_from: :component_3}}'
      )
    end

    feature "component init/3 action executes exactly once", %{session: session} do
      session
      |> visit(Page17)
      |> assert_text(css("#component_19_result"), "{:component_19_action_a, 1}")
      |> click(button("Run Component 19 Action B"))
      |> assert_text(css("#component_19_result"), "{:component_19_action_b, 1}")
    end

    # The order of execution is based on CIDs in ascending alphabetical order
    # (page's CID is "page", layout's CID is "layout")
    feature "all actions queued in server-side inits are executed in deterministic order", %{
      session: session
    } do
      session
      |> visit(Page6)
      |> assert_text(
        css("#combined_result"),
        "[:component_5_action_executed, :component_9_action_executed, :layout_action_executed, :component_7_action_executed, :page_action_executed, :component_6_action_executed]"
      )
    end
  end

  describe "actions queued in component client-side init/2" do
    feature "target not specified", %{session: session} do
      session
      |> visit(Page8)
      |> assert_text("Component11 is hidden")
      |> click(button("Show component"))
      |> assert_text(
        css("#component_11_result"),
        ~s'{:component_11_action_result, %{queued_from: :component_11}}'
      )
    end

    feature "target specified", %{session: session} do
      session
      |> visit(Page7)
      |> assert_text(css("#page_result"), "nil")
      |> assert_text("Component10 is hidden")
      |> click(button("Show component"))
      |> assert_text(
        css("#page_result"),
        ~s'{:page_action_result, %{queued_from: :component_10}}'
      )
    end

    feature "component init/2 action executes exactly once", %{session: session} do
      session
      |> visit(Page18)
      |> assert_text("Component20 is hidden")
      |> click(button("Show component"))
      |> assert_text(css("#component_20_result"), "{:component_20_action_a, 1}")
      |> click(button("Run Component 20 Action B"))
      |> assert_text(css("#component_20_result"), "{:component_20_action_b, 1}")
    end

    # The order of execution is based on queued order (not on CIDs in ascending alphabetical order as for init/3)
    feature "all actions queued in client-side inits are executed in deterministic order", %{
      session: session
    } do
      session
      |> visit(Page9)
      |> assert_text(css("#combined_result"), "[]")
      |> assert_text("Components are hidden")
      |> click(button("Show components"))
      |> assert_text(
        css("#combined_result"),
        "[:component_12_action_executed, :component_14_action_executed, :component_16_action_executed, :component_13_action_executed]"
      )
    end
  end

  describe "with delay" do
    feature "queued in page init/3", %{session: session} do
      session
      |> visit(Page10)
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_10_executed")
    end

    feature "queued in component init/3", %{session: session} do
      session
      |> visit(Page11)
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_11_executed")
    end

    feature "queued in component init/2", %{session: session} do
      session
      |> visit(Page12)
      |> assert_text(css("#result"), "nil")
      |> click(button("Show component"))
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_12_executed")
    end

    feature "queued in another action", %{session: session} do
      session
      |> visit(Page14)
      |> assert_text(css("#result"), "nil")
      |> click(button("Run instant action"))
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_14_executed")
    end

    feature "queued in command", %{session: session} do
      session
      |> visit(Page13)
      |> assert_text(css("#result"), "nil")
      |> click(button("Push command"))
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_13_executed")
    end

    feature "queued in template", %{session: session} do
      session
      |> visit(Page15)
      |> assert_text(css("#result"), "nil")
      |> click(button("Run delayed action"))
      |> assert_text(css("#result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#result"), "nil")
      |> sleep(1_000)
      |> assert_text(css("#result"), ":delayed_action_15_executed")
    end
  end

  describe "pending actions and navigation" do
    # Positive control for the cancellation scenarios that follow: the same click schedules a
    # dispatch that fires when the user stays put.
    feature "a pending delayed action fires when the user stays on the page", %{session: session} do
      session
      |> visit(Page20)
      |> assert_text(css("#layout_result"), "nil")
      |> click(button("Run delayed layout action"))
      |> assert_text(css("#layout_result"), "nil")
      |> sleep(2_000)
      |> assert_text(css("#layout_result"), "nil")
      |> sleep(1_500)
      |> assert_text(css("#layout_result"), ~s/"layout_action_ran"/)
    end

    # The layout's cid is the same string on both pages, so the destination's registry answers
    # for it - a target that still resolves is no evidence the dispatch is still valid. Waiting
    # out the rest of the delay on the destination proves the dispatch was cancelled rather than
    # merely deferred: the layout is re-rendered there, so a post-navigation fire would show up
    # in its result.
    feature "navigating to another page cancels a pending action targeting the layout",
            %{session: session} do
      session
      |> visit(Page20)
      |> click(button("Run delayed layout action"))
      |> click(link("Page 21 link"))
      |> assert_page(Page21)
      |> assert_text("Page 21 title")
      |> sleep(3_500)
      |> assert_text(css("#layout_result"), "nil")
    end

    # The component is mounted on one page only, so after the navigation its cid is registered
    # nowhere and the dispatch resolves to nothing at all. Interacting with the destination
    # afterwards is what reads the browser log - an uncaught error from the stale dispatch
    # surfaces as a Wallaby.JSError on the next command, whatever the page shows.
    feature "navigating to another page cancels a pending action whose component is gone",
            %{session: session} do
      session
      |> visit(Page20)
      |> click(button("Run delayed component action"))
      |> click(link("Page 21 link"))
      |> assert_page(Page21)
      |> sleep(3_500)
      |> assert_text("Page 21 title")
    end

    # Going back restores the registry from a snapshot rather than from mount data, reaching the
    # cancellation down a different path than a forward navigation does.
    feature "going back to another page cancels a pending action targeting the layout",
            %{session: session} do
      session
      |> visit(Page21)
      |> click(link("Page 20 link"))
      |> assert_page(Page20)
      |> click(button("Run delayed layout action"))
      |> go_back()
      |> assert_page(Page21)
      |> sleep(3_500)
      |> assert_text(css("#layout_result"), "nil")
    end

    # The page cid resolves on the destination too, but to a different module - one with no
    # clause for the action the previous page scheduled. A dispatch that survives the navigation
    # raises there rather than merely doing the wrong thing.
    feature "navigating to another page cancels a pending action targeting the page",
            %{session: session} do
      session
      |> visit(Page20)
      |> click(button("Run delayed page action"))
      |> click(link("Page 21 link"))
      |> assert_page(Page21)
      |> sleep(3_500)
      |> assert_text("Page 21 title")
    end

    # Positive control for the continuation drop below: the same click arms a continuation that
    # fires when the user stays put, proving the fixture schedules a real one.
    feature "an async action's continuation fires when the user stays on the page",
            %{session: session} do
      session
      |> visit(Page22)
      |> click(button("Run async continuation action"))
      |> assert_text(css("#result"), "nil")
      |> sleep(3_000)
      |> assert_text(css("#result"), ":async_continuation_ran")
    end

    # The await spans the navigation, so the continuation is scheduled only after the swap - a
    # window the timer cancellation never covered, the timer being armed after it already ran.
    # The continuation inherits the page its parent ran on, and that page has been left; on the
    # destination it would raise, Page21 having no action clause for it, which the post-sleep
    # command would surface from the browser log as a Wallaby.JSError.
    feature "navigating to another page drops the continuation of an async action",
            %{session: session} do
      session
      |> visit(Page22)
      |> click(button("Run async continuation action"))
      |> click(link("Page 21 link"))
      |> assert_page(Page21)
      |> sleep(3_000)
      |> assert_text("Page 21 title")
    end
  end

  describe "one action at a time" do
    # A burst of events dispatched faster than a microtask tick, the way fast keyboard repeat
    # dispatches them. Each one must read the state the one before it wrote. The page's action/3
    # has a clause that awaits, which makes every clause of it commit its result a tick after
    # reading the state - the increment clause included.
    feature "every dispatch of a burst lands", %{session: session} do
      session
      |> visit(Page23)
      |> execute_script("""
      const button = document.getElementById("increment");

      for (let i = 0; i < 30; i++) {
        button.dispatchEvent(new MouseEvent("click", {bubbles: true}));
      }
      """)
      |> assert_text(css("#count"), "30")
    end

    # The slow action is still awaiting when the fast one is dispatched. Run side by side, the
    # fast one would read the log before the slow one wrote to it, and the slow one's write would
    # then replace the fast one's.
    feature "an action dispatched behind an asynchronous one waits for it", %{session: session} do
      session
      |> visit(Page23)
      |> execute_script("""
      for (const id of ["append_slow", "append_fast"]) {
        document.getElementById(id).dispatchEvent(new MouseEvent("click", {bubbles: true}));
      }
      """)
      |> assert_text(css("#log"), "[:slow, :fast]")
    end
  end

  # A page can start an action in two ways: by queueing one in init/3, and by dispatching one from
  # a script in its template. The script's dispatch is buffered on a document load and waits for
  # the page's code after a client-side navigation, and the order of the two actions is the same
  # either way.
  describe "actions a page starts with" do
    feature "run in the same order on a document load", %{session: session} do
      session
      |> visit(Page24, via: "load")
      |> assert_text(css("#log"), ~s/[init: "load", script: "load"]/)
    end

    feature "run in the same order after a client-side navigation", %{session: session} do
      session
      |> visit(Page25)
      |> click(link("Page 24 link"))
      |> assert_page(Page24, via: "link")
      |> assert_text(css("#log"), ~s/[init: "link", script: "link"]/)
    end
  end

  describe "one action at a time, per component" do
    # The page's action is still awaiting when the component's is dispatched. Only the page is
    # held: the component's action writes the component's state, which nothing is about to
    # overwrite.
    feature "another component's action runs while one awaits", %{session: session} do
      session
      |> visit(Page26)
      |> click(button("Await slowly"))
      |> click(button("Increment component 22"))
      |> assert_text(css("#component_22_count"), "1")
      |> assert_text(css("#page_result"), "nil")
    end

    # The awaiting action belongs to the page being left. The destination's page actions share
    # its cid and must not inherit its wait.
    feature "the destination is not held by an action awaiting on the page left",
            %{session: session} do
      session
      |> visit(Page26)
      |> click(button("Await forever"))
      |> click(link("Page 27 link"))
      |> assert_page(Page27)
      |> click(button("Put page 27 result"))
      |> assert_text(css("#page_result"), ~s/"Page 27 result"/)
    end
  end
end
