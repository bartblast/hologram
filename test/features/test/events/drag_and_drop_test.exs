defmodule HologramFeatureTests.Events.DragAndDropTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.DragAndDropPage
  alias HologramFeatureTests.Events.DragAndDropWindowPage

  # ChromeDriver can't drive a native drag and drop, so the tests dispatch the drag events from a
  # script, with a DataTransfer of their own. A script-built DataTransfer stays writable during
  # every event, so the placeholder can be read back after dispatch. dispatchEvent returns false
  # when a listener prevented the default.
  @dispatch_script """
  window.dispatchDrag = (selector, type, {data = {}, files = [], relatedSelector = null} = {}) => {
    const dataTransfer = new DataTransfer();

    for (const [format, value] of Object.entries(data)) {
      dataTransfer.setData(format, value);
    }

    for (const [name, content, mimeType] of files) {
      dataTransfer.items.add(new File([content], name, {type: mimeType}));
    }

    const relatedTarget = relatedSelector === null ? null : document.querySelector(relatedSelector);

    const event = new DragEvent(type, {bubbles: true, cancelable: true, dataTransfer, relatedTarget});
    const notPrevented = document.querySelector(selector).dispatchEvent(event);

    return {notPrevented, types: Array.from(dataTransfer.types)};
  };
  """

  defp dispatch_drag(session, selector, type, opts \\ "{}") do
    script_result(
      session,
      @dispatch_script <>
        "return window.dispatchDrag(#{inspect(selector)}, #{inspect(type)}, #{opts});"
    )
  end

  feature "$drop carries the drag data and types", %{session: session} do
    session = visit(session, DragAndDropPage)

    dispatch_drag(session, "#zone", "drop", ~s'{data: {"text/plain": "Buy milk"}}')

    assert_text(
      session,
      css("#result"),
      ~s'{:dropped, %{data: %{"text/plain" => "Buy milk"}, files: [], types: ["text/plain"]}}'
    )
  end

  feature "$drop carries the dropped files", %{session: session} do
    session = visit(session, DragAndDropPage)

    dispatch_drag(session, "#zone", "drop", ~s'{files: [["notes.txt", "hello", "text/plain"]]}')

    assert_text(
      session,
      css("#result"),
      ~s'{:dropped, %{data: %{}, files: [{"notes.txt", "text/plain", true}], types: ["Files"]}}'
    )
  end

  feature "$drag_start lets the drag start", %{session: session} do
    session = visit(session, DragAndDropPage)

    assert %{"notPrevented" => true} = dispatch_drag(session, "#item", "dragstart")
  end

  feature "$drag_start puts the placeholder on a drag that carries no data", %{session: session} do
    session = visit(session, DragAndDropPage)

    assert %{"types" => ["application/x-hologram"]} =
             dispatch_drag(session, "#item", "dragstart")

    assert_text(
      session,
      css("#result"),
      "{:drag_started, %{data: %{}, files: [], items: [], types: []}}"
    )
  end

  feature "$drag_start puts no placeholder on a drag that carries data", %{session: session} do
    session = visit(session, DragAndDropPage)

    assert %{"types" => ["text/plain"]} =
             dispatch_drag(session, "#item", "dragstart", ~s'{data: {"text/plain": "Buy flour"}}')
  end

  feature "$drag_start carries the drag data", %{session: session} do
    session = visit(session, DragAndDropPage)

    dispatch_drag(session, "#item", "dragstart", ~s'{data: {"text/plain": "Buy bread"}}')

    assert_text(
      session,
      css("#result"),
      ~s'{:drag_started, %{data: %{"text/plain" => "Buy bread"}, files: [], items: [%{kind: :string, type: "text/plain"}], types: ["text/plain"]}}'
    )
  end

  feature "a $drop binding makes the element a drop target", %{session: session} do
    session = visit(session, DragAndDropPage)

    # A drag over a drop target mostly lands on what's inside it.
    assert %{"notPrevented" => false} = dispatch_drag(session, "#target_child", "dragenter")
    assert %{"notPrevented" => false} = dispatch_drag(session, "#target_child", "dragover")
    assert %{"notPrevented" => false} = dispatch_drag(session, "#target_child", "drop")
  end

  feature "a nil $drop binding leaves the element alone", %{session: session} do
    session = visit(session, DragAndDropPage)

    assert %{"notPrevented" => true} = dispatch_drag(session, "#nil_target_child", "dragenter")
    assert %{"notPrevented" => true} = dispatch_drag(session, "#nil_target_child", "dragover")
    assert %{"notPrevented" => true} = dispatch_drag(session, "#nil_target_child", "drop")
  end

  feature "$drag_enter and $drag_leave fire only at the element's edge", %{session: session} do
    session = visit(session, DragAndDropPage)

    # Into the zone from outside the page, onto its child and back, then out of the zone onto
    # another element. The browser fires dragenter on the element entered before dragleave on the
    # one left.
    dispatch_drag(session, "#zone", "dragenter")
    dispatch_drag(session, "#zone_child", "dragenter", ~s'{relatedSelector: "#zone"}')
    dispatch_drag(session, "#zone", "dragleave", ~s'{relatedSelector: "#zone_child"}')
    dispatch_drag(session, "#zone", "dragenter", ~s'{relatedSelector: "#zone_child"}')
    dispatch_drag(session, "#zone_child", "dragleave", ~s'{relatedSelector: "#zone"}')
    dispatch_drag(session, "#zone", "dragleave", ~s'{relatedSelector: "#item"}')

    session
    |> assert_text(css("#leave_count"), "1")
    |> assert_text(css("#enter_count"), "1")
  end

  feature "a <window> $drop gets a drop anywhere on the page", %{session: session} do
    session = visit(session, DragAndDropWindowPage)

    assert %{"notPrevented" => false} = dispatch_drag(session, "#area", "dragover")

    assert %{"notPrevented" => false} =
             dispatch_drag(session, "#area", "drop", ~s'{data: {"text/plain": "Buy eggs"}}')

    assert_text(session, css("#result"), ~s'{:dropped, %{"text/plain" => "Buy eggs"}}')
  end
end
