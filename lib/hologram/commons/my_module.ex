defmodule MyModule do
  import DateTime

  def my_fun do
    anon = &abc/1
    anon_2 = &to_date/1
    {anon, anon_2}
  end

  def abc(x) do
    123 + x
  end
end
