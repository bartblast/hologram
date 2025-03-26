defmodule Hologram.JSTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.JS

  test "exec/1" do
    code = "console.log('Hello, world!');"
    assert exec(code) == code
  end

  test "sigil_JS/2" do
    assert Code.eval_string("~JS\"console.log('Hello, world!');\"", [], __ENV__) ==
             {"console.log('Hello, world!');", []}
  end
end
