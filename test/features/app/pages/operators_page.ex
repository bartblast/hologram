defmodule HologramFeatureTests.OperatorsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import HologramFeatureTests.Operators, only: [+++: 2]
  import Kernel, except: [+: 2, inspect: 1]

  route "/operators"

  layout HologramFeatureTests.Components.DefaultLayout

  @boolean_a true
  @boolean_b false

  @float_a 123.0

  @integer_a 123
  @integer_b 234
  @integer_c 345

  @list_a [1, 2, 3]
  @list_b [2, 3, 4]

  @map_a %{a: @integer_a, b: @integer_b}

  @range_a @integer_a..@integer_c

  @string_a "aaa"
  @string_b "bbb"

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <h2><code>Overridable General Operators</code></h2>
      <button id="unary+" $click="unary+"> unary + </button>
      <button id="unary-" $click="unary-"> unary - </button>
      <button id="+" $click="+"> + </button>
      <button id="-" $click="-"> - </button>
      <button id="*" $click="*"> * </button>
      <button id="/" $click="/"> / </button>
      <button id="++" $click="++"> ++ </button>
      <button id="--" $click="--"> -- </button>
      <button id="and" $click="and"> and </button>
      <button id="&amp;&amp;" $click="&&"> &amp;&amp; </button>
      <button id="or" $click="or"> or </button>
      <button id="||" $click="||"> || </button>
      <button id="not" $click="not"> not </button>
      <button id="!" $click="!"> ! </button>
      <button id="in (list)" $click="in (list)"> in (list) </button>
      <button id="in (map)" $click="in (map)"> in (map) </button>
      <button id="in (range)" $click="in (range)"> in (range) </button>
      <button id="not in (list)" $click="not in (list)"> not in (list) </button>
      <button id="not in (map)" $click="not in (map)"> not in (map) </button>
      <button id="not in (range)" $click="not in (range)"> not in (range) </button>
      <button id="@" $click="@"> @ </button>
      <button id=".." $click=".."> .. </button>
      <button id="..//" $click="..//"> ..// </button>
      <button id="<>" $click="<>"> &lt;&gt; </button>
      <button id="|>" $click="|>"> |&gt; </button>
    </p>
    <p>
      <h2><code>Special Form Operators</code></h2>
      <button id="^" $click="^"> ^ </button>
      <button id=". (remote call)" $click=". (remote call)"> . (remote call) </button>
      <button id=". (anonymous function call)" $click=". (anonymous function call)"> . (anonymous function call) </button>
      <button id=". (map access)" $click=". (map access)"> . (map access) </button>
      <button id="=" $click="="> = </button>
      <button id="& (remote function)" $click="& (remote function)"> & (remote function) </button>
      <button id="& (local function)" $click="& (local function)"> & (local function) </button>
      <button id="& (anonymous function)" $click="& (anonymous function)"> & (anonymous function) </button>
      <button id="::" $click="::"> :: </button>
    </p>
    <p>
      <h2><code>Comparison Operators</code></h2>
      <button id="==" $click="=="> == </button>
      <button id="===" $click="==="> === </button>
      <button id="!=" $click="!="> != </button>
      <button id="!==" $click="!=="> !== </button>
      <button id="<" $click="<"> &lt; </button>
      <button id=">" $click=">"> &gt; </button>
      <button id="<=" $click="<="> &lt;= </button>
      <button id=">=" $click=">="> &gt;= </button>
    </p>
    <p>
      <h2><code>Custom and Overriden Operators</code></h2>
      <button id="+++ (custom)" $click="+++ (custom)"> +++ (custom) </button>
      <button id="+ (overriden)" $click="+ (overriden)"> + (overriden) </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:"unary+", _params, component) do
    put_state(component, :result, +@integer_a)
  end

  def action(:"unary-", _params, component) do
    put_state(component, :result, -@integer_a)
  end

  def action(:+, _params, component) do
    import Kernel, only: [+: 2, @: 1]
    put_state(component, :result, @integer_a + @integer_b)
  end

  def action(:-, _params, component) do
    put_state(component, :result, @integer_a - @integer_b)
  end

  def action(:*, _params, component) do
    put_state(component, :result, @integer_a * @integer_b)
  end

  def action(:/, _params, component) do
    put_state(component, :result, @integer_a / @integer_b)
  end

  def action(:++, _params, component) do
    put_state(component, :result, @list_a ++ @list_b)
  end

  def action(:--, _params, component) do
    put_state(component, :result, @list_a -- @list_b)
  end

  def action(:and, _params, component) do
    put_state(component, :result, wrap_term(@boolean_a) and wrap_term(@boolean_b))
  end

  def action(:&&, _params, component) do
    put_state(component, :result, wrap_term(@boolean_a) && wrap_term(@boolean_b))
  end

  def action(:or, _params, component) do
    put_state(component, :result, wrap_term(@boolean_a) or wrap_term(@boolean_b))
  end

  def action(:||, _params, component) do
    put_state(component, :result, wrap_term(@boolean_a) || wrap_term(@boolean_b))
  end

  def action(:not, _params, component) do
    put_state(component, :result, not @boolean_a)
  end

  def action(:!, _params, component) do
    put_state(component, :result, !wrap_term(@boolean_a))
  end

  def action(:"in (list)", _params, component) do
    put_state(component, :result, @integer_a in @list_a)
  end

  def action(:"in (map)", _params, component) do
    put_state(component, :result, {:a, @integer_a} in @map_a)
  end

  def action(:"in (range)", _params, component) do
    put_state(component, :result, @integer_b in @range_a)
  end

  def action(:"not in (list)", _params, component) do
    put_state(component, :result, @integer_a not in @list_a)
  end

  def action(:"not in (map)", _params, component) do
    put_state(component, :result, {:a, @integer_a} not in @map_a)
  end

  def action(:"not in (range)", _params, component) do
    put_state(component, :result, @integer_b not in @range_a)
  end

  def action(:@, _params, component) do
    put_state(component, :result, @integer_c)
  end

  def action(:.., _params, component) do
    put_state(component, :result, @integer_a..@integer_b)
  end

  def action(:..//, _params, component) do
    put_state(component, :result, @integer_a..@integer_b//@integer_c)
  end

  def action(:<>, _params, component) do
    put_state(component, :result, @string_a <> @string_b)
  end

  def action(:^, _params, component) do
    result = @integer_b
    {@integer_a, ^result} = {@integer_a, @integer_b}

    put_state(component, :result, result)
  end

  def action(:|>, _params, component) do
    result =
      @integer_a
      |> fun_1()
      |> fun_2()

    put_state(component, :result, result)
  end

  def action(:". (remote call)", _params, component) do
    module = Enum
    result = module.reverse([@integer_c, @integer_b, @integer_a])

    put_state(component, :result, result)
  end

  def action(:". (anonymous function call)", _params, component) do
    fun = fn n -> n * n end
    result = fun.(@integer_c)

    put_state(component, :result, result)
  end

  def action(:". (map access)", _params, component) do
    map = %{a: @integer_a, b: @integer_b}
    result = map.b

    put_state(component, :result, result)
  end

  def action(:=, _params, component) do
    result = @integer_a
    put_state(component, :result, result)
  end

  def action(:"& (remote function)", _params, component) do
    fun = &Enum.reverse/1
    result = fun.([@integer_c, @integer_b, @integer_a])

    put_state(component, :result, result)
  end

  def action(:"& (local function)", _params, component) do
    fun = &fun_3/1
    result = fun.(@integer_a)

    put_state(component, :result, result)
  end

  def action(:"& (anonymous function)", _params, component) do
    fun = &(&1 * 5)
    result = fun.(@integer_a)

    put_state(component, :result, result)
  end

  def action(:"::", _params, component) do
    x = @float_a
    result = <<x::float>>

    put_state(component, :result, result)
  end

  def action(:==, _params, component) do
    put_state(component, :result, wrap_term(@integer_a) == wrap_term(@integer_a))
  end

  def action(:===, _params, component) do
    put_state(component, :result, wrap_term(@integer_a) === wrap_term(@float_a))
  end

  def action(:!=, _params, component) do
    put_state(component, :result, @integer_a != @integer_b)
  end

  def action(:!==, _params, component) do
    put_state(component, :result, @integer_a !== @float_a)
  end

  def action(:<, _params, component) do
    put_state(component, :result, @integer_a < @integer_b)
  end

  def action(:>, _params, component) do
    put_state(component, :result, @integer_b > @integer_a)
  end

  def action(:<=, _params, component) do
    put_state(component, :result, @integer_a <= @integer_b)
  end

  def action(:>=, _params, component) do
    put_state(component, :result, @integer_b >= @integer_a)
  end

  def action(:"+++ (custom)", _params, component) do
    put_state(component, :result, @integer_a +++ @integer_b)
  end

  def action(:"+ (overriden)", _params, component) do
    import HologramFeatureTests.Operators, only: [+: 2]
    put_state(component, :result, @integer_a + @integer_b)
  end

  def fun_1(arg), do: arg * 2

  def fun_2(arg), do: arg * 3

  def fun_3(arg), do: arg * 4
end
