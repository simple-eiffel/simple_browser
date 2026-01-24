# S03: CONTRACTS

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## SIMPLE_BROWSER Contracts

### Feature: navigate_to
```eiffel
navigate_to (a_url: READABLE_STRING_GENERAL)
    require
        valid: is_valid
```

### Feature: navigate (fluent)
```eiffel
navigate (a_url: READABLE_STRING_GENERAL): like Current
    require
        valid: is_valid
    ensure
        result_is_current: Result = Current
```

### Feature: with_html (fluent)
```eiffel
with_html (a_html: READABLE_STRING_GENERAL): like Current
    require
        valid: is_valid
    ensure
        result_is_current: Result = Current
```

### Feature: on_call
```eiffel
on_call (a_name: READABLE_STRING_GENERAL; a_handler: PROCEDURE [TUPLE [STRING_8, STRING_8]])
    require
        valid: is_valid
        name_not_empty: not a_name.is_empty
```

### Feature: respond
```eiffel
respond (a_seq: STRING_8; a_result: STRING_8)
    require
        valid: is_valid
```

### Feature: run
```eiffel
run
    require
        valid: is_valid
```

## BROWSER_ENGINE Contracts

### Feature: navigate
```eiffel
navigate (a_url: READABLE_STRING_GENERAL)
    require
        ready: is_ready
        url_not_empty: not a_url.is_empty
```

### Feature: set_size
```eiffel
set_size (a_width, a_height: INTEGER; a_hints: INTEGER)
    require
        ready: is_ready
        valid_width: a_width > 0
        valid_height: a_height > 0
        valid_hints: a_hints >= Size_hint_none and a_hints <= Size_hint_fixed
```

### Feature: bind
```eiffel
bind (a_name: READABLE_STRING_GENERAL; a_callback: PROCEDURE [TUPLE [seq: STRING_8; req: STRING_8]])
    require
        ready: is_ready
        name_not_empty: not a_name.is_empty
        callback_attached: a_callback /= Void
```

### Feature: dispose
```eiffel
dispose
    ensure
        not_ready: not is_ready
```

## SIMPLE_BROWSER Invariants

```eiffel
invariant
    engine_exists: engine /= Void
```

## WEBVIEW_ENGINE Invariants

```eiffel
invariant
    valid_when_ready: is_ready implies ctx /= default_pointer
    callback_registry_exists: callback_registry /= Void
```
