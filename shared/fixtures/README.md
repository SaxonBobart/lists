# Fixtures

Golden parser inputs for the shared file format.

Future platform parsers should:

1. Read every `.list.yml` and item `.md` file.
2. Parse to the platform model.
3. Re-emit.
4. Assert the output is stable enough not to dirty every file on save.

Keep fixtures small, synthetic, and free of personal data.
