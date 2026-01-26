# Erlang Time Functions Porting Strategy

This strategy is based on the official [Erlang Time and Time Correction documentation](https://www.erlang.org/doc/apps/erts/time_correction).

## Background

Erlang's time system is built on this core relationship:

```
Erlang System Time = Erlang Monotonic Time + Time Offset
```

This means the functions are interconnected, and we should structure our implementations to reflect these dependencies.

## Architecture

### Layer 1: Base Functions (JS API abstraction)

These are the **only** functions that should directly use JavaScript APIs:

| Function | JS API | Notes |
|----------|--------|-------|
| `:os.system_time/0` | `Date.now()` | Convert to nanoseconds |
| `:erlang.monotonic_time/0` | `performance.now()` | Convert to nanoseconds |

All other functions should delegate to these rather than calling JS APIs directly.

### Layer 2: Utility

| Function | Implementation |
|----------|----------------|
| `:erlang.convert_time_unit/3` | Pure math conversion between time units |

Supported units: `second`, `millisecond`, `microsecond`, `nanosecond`, `native`

**Note:** `native` unit = nanoseconds (since `performance.now()` precision is 100ns)

### Layer 3: Derived Erlang functions

| Function | Implementation |
|----------|----------------|
| `:erlang.time_offset/0` | `os.system_time() - erlang.monotonic_time()` |
| `:erlang.system_time/0` | Delegate to `:os.system_time/0` |

### Layer 4: Unit variants

All `/1` variants should delegate to their `/0` counterpart + `convert_time_unit/3`:

| Function | Implementation |
|----------|----------------|
| `:os.system_time/1` | `convert_time_unit(os.system_time(), :native, unit)` |
| `:erlang.monotonic_time/1` | `convert_time_unit(erlang.monotonic_time(), :native, unit)` |
| `:erlang.system_time/1` | `convert_time_unit(erlang.system_time(), :native, unit)` |
| `:erlang.time_offset/1` | `convert_time_unit(erlang.time_offset(), :native, unit)` |

### Layer 5: Independent

| Function | Implementation |
|----------|----------------|
| `:erlang.localtime/0` | `new Date()` with local timezone methods, returns `{{Year, Month, Day}, {Hour, Minute, Second}}` |

## Dependency Graph

```
Layer 1 (Base functions):
    Date.now()  ─────────────►  :os.system_time/0
    performance.now()  ──────►  :erlang.monotonic_time/0

Layer 2 (Utility):
    :erlang.convert_time_unit/3  (no dependencies, pure math)

Layer 3 (Derived):
    :os.system_time/0  ──────►  :erlang.system_time/0

    :os.system_time/0
            +                ──►  :erlang.time_offset/0
    :erlang.monotonic_time/0

Layer 4 (Unit variants):
    :foo/0 + :erlang.convert_time_unit/3  ──►  :foo/1
```

## Implementation Order

If you're implementing multiple functions, this order respects dependencies:

1. `:os.system_time/0`
2. `:erlang.monotonic_time/0`
3. `:erlang.convert_time_unit/3`
4. `:erlang.time_offset/0`
5. `:erlang.system_time/0`
6. All `/1` variants
7. `:erlang.localtime/0`

## Why This Strategy?

1. **Single abstraction point**: Only two functions interact with JS APIs. Any future changes to the underlying JS APIs only require updating these two functions.
2. **Mirrors Erlang's design**: Base functions provide raw values, derived functions build on top.
3. **Consistency**: All `/1` variants work the same way (delegate to `/0` + convert).
4. **Testability**: Derived functions can be tested by verifying they correctly delegate to the base functions.
