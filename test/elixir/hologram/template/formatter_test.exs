defmodule Hologram.Template.FormatterTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Formatter
  alias Hologram.TemplateSyntaxError

  # Who knows? This might be useful someday
  # Regardless it makes the empty list more meaningful
  @test_opts []
  # Similarly here, it's just easier to work out
  defp format_as_binary(t) do
    t |> format(@test_opts) |> IO.iodata_to_binary()
  end

  describe "format/2" do
    test "fairly standard" do
      malformed =
        "<html><body><div id=\"test\"><span $click=\"say_hi\" title=\"look here!\"  >hi!</span></div></body></html>\n"

      proper = """
      <html>
        <body>
          <div id="test">
            <span $click="say_hi" title="look here!">hi!</span>
          </div>
        </body>
      </html>
      """

      assert format_as_binary(malformed) == proper
      # Second verse, same as the first
      assert format_as_binary(proper) == proper
    end

    test "crazy whitespace with self-closing" do
      malformed = """

      <div>
            <MyWidget       extra={ @nonsense } plus={@more}/>
        </div>

      """

      proper = """
      <div>
        <MyWidget extra={@nonsense} plus={@more} />
      </div>
      """

      assert format_as_binary(malformed) == proper
    end

    test "text embedded directly in block" do
      malformed = "<div id=\"test\">Text</div>\n"

      proper = """
      <div id="test">
        Text
      </div>
      """

      assert format_as_binary(malformed) == proper
    end

    test "tags in text in block" do
      malformed = """
      <div>Please <a href="mailto:test@example.com"><em>email</em> me</a> with questions.</div>
      """

      proper = """
      <div>
        Please <a href="mailto:test@example.com"><em>email</em> me</a> with questions.
      </div>
      """

      assert format_as_binary(malformed) == proper
    end

    test "dual purpose attribute" do
      malformed = """
      <div class="first {@second}     carriage">
      <p>Please enjoy the <a href="#bottom">silence</a>.

      </p>
      </div>
      """

      proper = """
      <div class="first {@second}" carriage"">
        <p>
          Please enjoy the <a href="#bottom">silence</a>.
        </p>
      </div>
      """

      assert format_as_binary(malformed) == proper
    end
  end

  # The parser is tested elsewhere.
  # Popping back the syntax error and bailing feels like the best
  # course of action for a formatter.
  # Mostly testing things which might choke the formatter if they made it through
  describe "unparseable templates" do
    test "improper closing tag" do
      malformed = "<body><div>text</div</body>"
      assert_raise TemplateSyntaxError, fn -> format(malformed, @test_opts) end
    end

    test "unquoted attributes" do
      malformed = "<body><div id=test>text</div></body>"
      assert_raise TemplateSyntaxError, fn -> format(malformed, @test_opts) end
    end
  end
end
