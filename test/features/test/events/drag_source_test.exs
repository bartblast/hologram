defmodule HologramFeatureTests.Events.DragSourceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.DragSourcePage

  # ChromeDriver can't drive a native drag and drop, so the tests dispatch the drag events from a
  # script, with a DataTransfer of their own. Chrome ignores the allowed effects, the drop effect
  # and the drag image set on a DataTransfer a script built, so the script records them instead. The given
  # data stands for what the browser puts on a drag before the page's listeners run.
  @drag_script """
  window.dispatchDrag = (selector, type, data = {}) => {
    const dataTransfer = new DataTransfer();
    const dragImages = [];

    for (const [format, value] of Object.entries(data)) {
      dataTransfer.setData(format, value);
    }

    const recorded = {dropEffect: "none", effectAllowed: "uninitialized"};

    for (const property of ["dropEffect", "effectAllowed"]) {
      Object.defineProperty(dataTransfer, property, {
        get: () => recorded[property],
        set: (value) => (recorded[property] = value)
      });
    }

    dataTransfer.setDragImage = (element, x, y) => dragImages.push([element.id, x, y]);

    const event = new DragEvent(type, {bubbles: true, cancelable: true, dataTransfer});
    document.querySelector(selector).dispatchEvent(event);

    return {
      data: Object.fromEntries(
        Array.from(dataTransfer.types).map((format) => [format, dataTransfer.getData(format)])
      ),
      dragImages,
      dropEffect: dataTransfer.dropEffect,
      effectAllowed: dataTransfer.effectAllowed
    };
  };
  """

  defp dispatch_drag(session, selector, type, data \\ "{}") do
    script_result(
      session,
      @drag_script <>
        "return window.dispatchDrag(#{inspect(selector)}, #{inspect(type)}, #{data});"
    )
  end

  feature "$data_transfer puts the drag data on the drag", %{session: session} do
    session = visit(session, DragSourcePage)

    assert %{"data" => data} = dispatch_drag(session, "#item", "dragstart")
    assert data == %{"application/x-task" => "42", "text/plain" => "Buy milk"}
  end

  feature "$data_transfer keeps the browser's own data on the drag", %{session: session} do
    session = visit(session, DragSourcePage)

    # A link inside the source drags with what the browser puts on a link, and the source's
    # declaration, whose nil removes the link's URL.
    assert %{"data" => data} =
             dispatch_drag(
               session,
               "#item_link",
               "dragstart",
               ~s'{"text/html": "<a href=\\"https://example.com\\">Link</a>", "text/uri-list": "https://example.com"}'
             )

    assert data == %{
             "application/x-task" => "42",
             "text/html" => ~s'<a href="https://example.com">Link</a>',
             "text/plain" => "Buy milk"
           }
  end

  feature "$data_transfer puts the drag data on the drag before $drag_start reads it", %{
    session: session
  } do
    session = visit(session, DragSourcePage)

    dispatch_drag(session, "#item", "dragstart")

    assert_text(
      session,
      css("#result"),
      ~s'{:drag_started, %{"application/x-task" => "42", "text/plain" => "Buy milk"}}'
    )
  end

  feature "$data_transfer sets the allowed effects", %{session: session} do
    session = visit(session, DragSourcePage)

    assert %{"effectAllowed" => "move"} = dispatch_drag(session, "#item", "dragstart")
  end

  feature "$data_transfer sets the drag image", %{session: session} do
    session = visit(session, DragSourcePage)

    assert %{"dragImages" => [["preview", 16, 8]]} = dispatch_drag(session, "#item", "dragstart")
  end

  feature "the nearest $data_transfer source makes the drag", %{session: session} do
    session = visit(session, DragSourcePage)

    result = dispatch_drag(session, "#chip", "dragstart")

    assert result == %{
             "data" => %{"application/x-tag" => "urgent"},
             "dragImages" => [],
             "dropEffect" => "none",
             "effectAllowed" => "uninitialized"
           }
  end

  feature "$data_transfer sets the drop effect on a drop target", %{session: session} do
    session = visit(session, DragSourcePage)

    # A drag over a drop target mostly lands on what's inside it.
    assert %{"dropEffect" => "move"} = dispatch_drag(session, "#zone_child", "dragover")

    assert_text(session, css("#result"), "{:dragged_over, :move}")
  end

  feature "the nearest drop target's drop effect wins", %{session: session} do
    session = visit(session, DragSourcePage)

    assert %{"dropEffect" => "link"} = dispatch_drag(session, "#inner_zone_child", "dragover")

    assert_text(session, css("#result"), "{:dragged_over, :link}")
  end
end
