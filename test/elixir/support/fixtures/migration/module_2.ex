# A calendar a datetime can name that compares with ISO but throws while the datetime is printed.
defmodule Hologram.Test.Fixtures.Migration.Module2 do
  defdelegate day_rollover_relative_to_midnight_utc, to: Calendar.ISO

  defdelegate naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond),
    to: Calendar.ISO

  defdelegate valid_date?(year, month, day), to: Calendar.ISO
  defdelegate valid_time?(hour, minute, second, microsecond), to: Calendar.ISO

  @spec datetime_to_string(
          integer,
          integer,
          integer,
          integer,
          integer,
          integer,
          tuple,
          String.t(),
          String.t(),
          integer,
          integer
        ) :: no_return
  # The arity is the one Calendar's datetime_to_string/11 callback has.
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def datetime_to_string(
        _year,
        _month,
        _day,
        _hour,
        _minute,
        _second,
        _us,
        _zone,
        _abbr,
        _utc,
        _std
      ),
      do: throw(:calendar_threw)
end
