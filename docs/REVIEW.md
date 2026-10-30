# Review log

## Review items
(📝 things for the user to judge)

## Needs user action
- **Environment:** This work was done in a Linux x86_64 cloud container (no GPU, no macOS). Everything needing the M5 Mac, a GPU,
  a window, or large model weights is listed in `docs/LOCAL_TODO.md`.
- `OPENROUTER_API_KEY` was not available and `openrouter.ai` is blocked from the container: live LLM probes are DEFERRED.

## Deferred / fallbacks used
- **M0-T03:** PLAN says autoload stubs get `class_name`; Godot rejects a class_name equal to an autoload name, so autoloads have none and are referenced by their autoload name. Helper classes (GameDate etc.) do use class_name.
