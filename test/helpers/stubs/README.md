# Stubs

Each file in this directory is a fake of a system command. When a test calls
`jr_use_stub <name>`, the stub is symlinked into a per-test bin/ that's prepended
to PATH. The stub logs its argv to `${JR_STUB_LOG}` and exits 0.

Add a new stub by dropping a script here, marking it executable, and naming it
after the command it shadows.
