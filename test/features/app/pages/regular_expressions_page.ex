defmodule HologramFeatureTests.RegularExpressionsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  route "/regular-expressions"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button id="client-sent regex" $click="client-sent regex"> client-sent regex </button>
      <button id="dynamic compilation" $click="dynamic compilation"> dynamic compilation </button>
      <button id="match operator" $click="match operator"> match operator </button>
      <button id="named captures" $click="named captures"> named captures </button>
      <button id="regex match?" $click="regex match?"> regex match? </button>
      <button id="regex replace" $click="regex replace"> regex replace </button>
      <button id="regex run" $click="regex run"> regex run </button>
      <button id="regex scan" $click="regex scan"> regex scan </button>
      <button id="regex split" $click="regex split"> regex split </button>
      <button id="server-sent regex" $click={command: :"server-sent regex"}> server-sent regex </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:"client-sent regex", _params, component) do
    regex = Regex.compile!("g+h")
    put_command(component, :"client-sent regex echo", regex: regex)
  end

  def action(:"client-sent regex result", params, component) do
    put_state(component, :result, params.result)
  end

  def action(:"dynamic compilation", _params, component) do
    regex = Regex.compile!(wrap_term("b") <> "+")
    put_state(component, :result, Regex.run(regex, "abbc"))
  end

  def action(:"match operator", _params, component) do
    put_state(component, :result, wrap_term("aaa bbb") =~ ~r/b+/)
  end

  def action(:"named captures", _params, component) do
    put_state(component, :result, Regex.named_captures(~r/(?<number>\d+)/, "no 42"))
  end

  def action(:"regex match?", _params, component) do
    put_state(component, :result, Regex.match?(~r/xyz/, "abc"))
  end

  def action(:"regex replace", _params, component) do
    put_state(component, :result, Regex.replace(~r/b+/, "abbc", "X"))
  end

  def action(:"regex run", _params, component) do
    put_state(component, :result, Regex.run(~r/a(b+)/, "xabbc"))
  end

  def action(:"regex scan", _params, component) do
    put_state(component, :result, Regex.scan(~r/[13]/, "123"))
  end

  def action(:"regex split", _params, component) do
    put_state(component, :result, Regex.split(~r/,/, "1,2,3"))
  end

  def action(:"server-sent regex result", params, component) do
    put_state(component, :result, Regex.run(params.regex, "xeefy"))
  end

  def command(:"client-sent regex echo", params, server) do
    result = Regex.run(params.regex, "xggghy")
    put_action(server, :"client-sent regex result", result: result)
  end

  def command(:"server-sent regex", _params, server) do
    put_action(server, :"server-sent regex result", regex: ~r/e+f/)
  end
end
